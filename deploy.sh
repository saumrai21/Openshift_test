#!/usr/bin/env bash
# =============================================================================
# deploy.sh — One-click TFE on OpenShift (GCP) deployment
# Usage: ./scripts/deploy.sh [--env dev|prod] [--skip-infra] [--skip-tfe]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────
ENV="prod"
SKIP_INFRA=false
SKIP_TFE=false
DRY_RUN=false
LOG_FILE="${ROOT_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*" | tee -a "${LOG_FILE}"; }
ok()   { echo -e "${GREEN}[✔]${NC} $*" | tee -a "${LOG_FILE}"; }
warn() { echo -e "${YELLOW}[⚠]${NC} $*" | tee -a "${LOG_FILE}"; }
fail() { echo -e "${RED}[✘]${NC} $*" | tee -a "${LOG_FILE}"; exit 1; }
banner(){ echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${NC}"; \
          echo -e "${BOLD}${CYAN}  $*${NC}"; \
          echo -e "${BOLD}${CYAN}══════════════════════════════════════${NC}\n"; }

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --env)        ENV="$2"; shift 2 ;;
    --skip-infra) SKIP_INFRA=true; shift ;;
    --skip-tfe)   SKIP_TFE=true; shift ;;
    --dry-run)    DRY_RUN=true; shift ;;
    --help|-h)
      echo "Usage: $0 [--env dev|prod] [--skip-infra] [--skip-tfe] [--dry-run]"
      exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

ENV_DIR="${ROOT_DIR}/terraform/environments/${ENV}"
[[ -f "${ENV_DIR}/terraform.tfvars" ]] || \
  fail "Missing ${ENV_DIR}/terraform.tfvars — copy from terraform.tfvars.example"

# ── Load vars for use in shell ────────────────────────────────────────────────
# shellcheck disable=SC1090
eval "$(grep -E '^[a-z_]+\s*=' "${ENV_DIR}/terraform.tfvars" \
        | sed 's/ *= */=/;s/^/export TFE_VAR_/')"

banner "TFE on OpenShift/GCP — Deployment [${ENV}]"
log "Log file: ${LOG_FILE}"

# ── Step 1: Preflight checks ──────────────────────────────────────────────────
banner "Step 1 — Preflight checks"
"${SCRIPT_DIR}/preflight.sh" || fail "Preflight checks failed"
ok "All prerequisites satisfied"

# ── Step 2: GCP Auth ──────────────────────────────────────────────────────────
banner "Step 2 — GCP Authentication"
if ! gcloud auth print-access-token &>/dev/null; then
  log "No active GCP credentials found — running gcloud auth login..."
  gcloud auth login --update-adc
fi
ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)
ok "Authenticated as: ${ACTIVE_ACCOUNT}"

PROJECT_ID=$(grep 'project_id' "${ENV_DIR}/terraform.tfvars" | awk -F'"' '{print $2}')
gcloud config set project "${PROJECT_ID}" --quiet
ok "Active project: ${PROJECT_ID}"

# ── Step 3: Enable required APIs ─────────────────────────────────────────────
banner "Step 3 — Enable GCP APIs"
APIS=(
  compute.googleapis.com
  container.googleapis.com
  sqladmin.googleapis.com
  redis.googleapis.com
  storage.googleapis.com
  secretmanager.googleapis.com
  iam.googleapis.com
  servicenetworking.googleapis.com
  cloudresourcemanager.googleapis.com
)
for api in "${APIS[@]}"; do
  log "Enabling ${api}..."
  gcloud services enable "${api}" --project="${PROJECT_ID}" --quiet
done
ok "All required APIs enabled"

# ── Step 4: Upload TFE license to Secret Manager ─────────────────────────────
banner "Step 4 — TFE License"
LICENSE_FILE="${ROOT_DIR}/terraform.hclic"
[[ -f "${LICENSE_FILE}" ]] || fail "terraform.hclic not found in repo root"
SECRET_NAME=$(grep 'tfe_license_secret' "${ENV_DIR}/terraform.tfvars" | awk -F'"' '{print $2}')
if ! gcloud secrets describe "${SECRET_NAME}" --project="${PROJECT_ID}" &>/dev/null; then
  log "Creating secret '${SECRET_NAME}' in GCP Secret Manager..."
  gcloud secrets create "${SECRET_NAME}" \
    --project="${PROJECT_ID}" \
    --replication-policy="automatic"
fi
gcloud secrets versions add "${SECRET_NAME}" \
  --project="${PROJECT_ID}" \
  --data-file="${LICENSE_FILE}"
ok "TFE license uploaded to Secret Manager as '${SECRET_NAME}'"

# ── Step 5: Terraform — GCP Infrastructure ───────────────────────────────────
if [[ "${SKIP_INFRA}" == false ]]; then
  banner "Step 5 — Terraform: GCP Infrastructure"
  pushd "${ENV_DIR}" > /dev/null
  terraform init -upgrade | tee -a "${LOG_FILE}"
  if [[ "${DRY_RUN}" == true ]]; then
    terraform plan -out=tfplan | tee -a "${LOG_FILE}"
    warn "Dry run — skipping apply"
  else
    terraform apply -auto-approve | tee -a "${LOG_FILE}"
  fi
  ok "GCP infrastructure provisioned"
  popd > /dev/null
else
  warn "Skipping infrastructure (--skip-infra)"
fi

# ── Step 6: Configure kubectl / oc ───────────────────────────────────────────
banner "Step 6 — Configure OpenShift CLI"
CLUSTER_NAME=$(grep 'ocp_cluster_name' "${ENV_DIR}/terraform.tfvars" | awk -F'"' '{print $2}')
REGION=$(grep '^region' "${ENV_DIR}/terraform.tfvars" | awk -F'"' '{print $2}')

# Fetch kubeconfig from GKE (OpenShift clusters provisioned via gke-ocp module)
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}"
ok "kubeconfig configured for cluster: ${CLUSTER_NAME}"

# ── Step 7: OpenShift namespaces + SCCs ──────────────────────────────────────
banner "Step 7 — OpenShift Namespaces & Security Contexts"
oc apply -f "${ROOT_DIR}/openshift/namespaces/" | tee -a "${LOG_FILE}"
oc apply -f "${ROOT_DIR}/openshift/storage/"    | tee -a "${LOG_FILE}"
ok "Namespaces and StorageClasses applied"

# ── Step 8: Install Operators ─────────────────────────────────────────────────
banner "Step 8 — Install Operators (cert-manager, external-secrets)"
oc apply -f "${ROOT_DIR}/openshift/operators/" | tee -a "${LOG_FILE}"
log "Waiting for operators to become ready (up to 5 min)..."
kubectl wait deployment \
  --for=condition=Available \
  --timeout=300s \
  -n cert-manager \
  --all 2>/dev/null || warn "cert-manager not ready yet — continuing"
ok "Operators installed"

# ── Step 9: Deploy TFE via Helm ───────────────────────────────────────────────
if [[ "${SKIP_TFE}" == false ]]; then
  banner "Step 9 — Deploy Terraform Enterprise"
  "${SCRIPT_DIR}/deploy-tfe.sh" --env "${ENV}" | tee -a "${LOG_FILE}"
  ok "TFE deployed"
else
  warn "Skipping TFE deployment (--skip-tfe)"
fi

# ── Step 10: Smoke tests ──────────────────────────────────────────────────────
banner "Step 10 — Smoke Tests"
if [[ "${DRY_RUN}" == false ]]; then
  "${SCRIPT_DIR}/smoke-test.sh" --env "${ENV}" | tee -a "${LOG_FILE}"
  ok "Smoke tests passed"
else
  warn "Dry run — skipping smoke tests"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
TFE_HOST=$(grep 'tfe_hostname' "${ENV_DIR}/terraform.tfvars" | awk -F'"' '{print $2}')
banner "🎉 Deployment Complete!"
echo -e "${GREEN}${BOLD}TFE URL:${NC}  https://${TFE_HOST}"
echo -e "${GREEN}${BOLD}Log:${NC}      ${LOG_FILE}"
echo ""
echo "Next steps:"
echo "  1. Create the initial admin user at https://${TFE_HOST}/admin/account/new"
echo "  2. Activate your license at https://${TFE_HOST}/app/admin/license"
echo "  3. Configure your first organization"
