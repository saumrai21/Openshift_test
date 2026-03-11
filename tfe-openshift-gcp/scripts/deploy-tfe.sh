#!/usr/bin/env bash
# deploy-tfe.sh — Deploy TFE operator + instance via Helm
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV="prod"

while [[ $# -gt 0 ]]; do
  case $1 in
    --env) ENV="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

ENV_DIR="${ROOT_DIR}/terraform/environments/${ENV}"
TFVARS="${ENV_DIR}/terraform.tfvars"

# ── Read values from tfvars ────────────────────────────────────────────────────
get_var() { grep "^${1}" "${TFVARS}" | awk -F'"' '{print $2}'; }

TFE_HOSTNAME=$(get_var tfe_hostname)
TFE_VERSION=$(get_var tfe_version)
TFE_REPLICAS=$(grep 'tfe_replicas' "${TFVARS}" | awk -F'=' '{print $2}' | tr -d ' ')
PROJECT_ID=$(get_var project_id)
REGION=$(get_var region)
TFE_LICENSE_SECRET=$(get_var tfe_license_secret)
TFE_ENC_SECRET=$(get_var tfe_encryption_password_secret)

# Resolve "latest" TFE version
if [[ "${TFE_VERSION}" == "latest" ]]; then
  echo "Resolving latest TFE version from HashiCorp releases..."
  TFE_VERSION=$(curl -fsSL \
    "https://api.releases.hashicorp.com/v1/releases/terraform-enterprise/latest" \
    | jq -r '.version' 2>/dev/null || echo "v202501-1")
  echo "Resolved TFE version: ${TFE_VERSION}"
fi

# ── Retrieve secrets from GCP Secret Manager ──────────────────────────────────
TFE_LICENSE=$(gcloud secrets versions access latest \
  --secret="${TFE_LICENSE_SECRET}" \
  --project="${PROJECT_ID}")

TFE_ENC_PASS=$(gcloud secrets versions access latest \
  --secret="${TFE_ENC_SECRET}" \
  --project="${PROJECT_ID}" 2>/dev/null || \
  openssl rand -hex 32)

# Store enc password if it was just generated
if ! gcloud secrets describe "${TFE_ENC_SECRET}" --project="${PROJECT_ID}" &>/dev/null; then
  gcloud secrets create "${TFE_ENC_SECRET}" \
    --project="${PROJECT_ID}" \
    --replication-policy="automatic"
  printf '%s' "${TFE_ENC_PASS}" | gcloud secrets versions add "${TFE_ENC_SECRET}" \
    --project="${PROJECT_ID}" \
    --data-file=-
fi

# ── Pull Terraform outputs ─────────────────────────────────────────────────────
pushd "${ENV_DIR}" > /dev/null
DB_HOST=$(terraform output -raw db_host 2>/dev/null || echo "")
DB_NAME=$(terraform output -raw db_name 2>/dev/null || echo "tfe")
DB_USER=$(terraform output -raw db_user 2>/dev/null || echo "tfe")
DB_PASS=$(terraform output -raw db_password 2>/dev/null || echo "")
REDIS_HOST=$(terraform output -raw redis_host 2>/dev/null || echo "")
REDIS_PORT=$(terraform output -raw redis_port 2>/dev/null || echo "6379")
GCS_BUCKET=$(terraform output -raw gcs_bucket 2>/dev/null || echo "")
TFE_SA_EMAIL=$(terraform output -raw tfe_sa_email 2>/dev/null || echo "")
popd > /dev/null

# ── Create TFE namespace ───────────────────────────────────────────────────────
oc apply -f "${ROOT_DIR}/openshift/namespaces/tfe-namespace.yaml"

# ── Create Kubernetes secrets ──────────────────────────────────────────────────
kubectl create secret generic tfe-secrets \
  --namespace=openshift-tfe \
  --from-literal=license="${TFE_LICENSE}" \
  --from-literal=enc_password="${TFE_ENC_PASS}" \
  --from-literal=db_password="${DB_PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -

# ── Add HashiCorp Helm repo ────────────────────────────────────────────────────
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update hashicorp

# ── Deploy TFE Operator ────────────────────────────────────────────────────────
echo "Installing TFE Operator..."
helm upgrade --install tfe-operator hashicorp/terraform-enterprise-operator \
  --namespace openshift-tfe \
  --create-namespace \
  --version ">=0.1.0" \
  --set installCRDs=true \
  --wait \
  --timeout 5m

# ── Deploy TFE Instance via custom Helm chart ──────────────────────────────────
echo "Deploying TFE instance (version ${TFE_VERSION})..."
helm upgrade --install tfe "${ROOT_DIR}/helm/tfe-chart" \
  --namespace openshift-tfe \
  --set tfe.hostname="${TFE_HOSTNAME}" \
  --set tfe.version="${TFE_VERSION}" \
  --set tfe.replicas="${TFE_REPLICAS}" \
  --set tfe.db.host="${DB_HOST}" \
  --set tfe.db.name="${DB_NAME}" \
  --set tfe.db.user="${DB_USER}" \
  --set tfe.storage.gcsBucket="${GCS_BUCKET}" \
  --set tfe.redis.host="${REDIS_HOST}" \
  --set tfe.redis.port="${REDIS_PORT}" \
  --set tfe.serviceAccount.email="${TFE_SA_EMAIL}" \
  --wait \
  --timeout 10m

echo "[✔] TFE Helm release deployed"
echo "    Monitor rollout: kubectl rollout status statefulset/tfe -n openshift-tfe"
