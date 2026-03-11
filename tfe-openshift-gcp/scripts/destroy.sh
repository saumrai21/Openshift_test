#!/usr/bin/env bash
# destroy.sh — Safely tear down TFE on OpenShift/GCP
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV="prod"

while [[ $# -gt 0 ]]; do
  case $1 in --env) ENV="$2"; shift 2 ;; *) shift ;; esac
done

echo -e "\033[0;31m[WARNING]\033[0m This will DESTROY all TFE resources in env: ${ENV}"
read -rp "Type 'destroy' to confirm: " CONFIRM
[[ "${CONFIRM}" == "destroy" ]] || { echo "Aborted."; exit 0; }

ENV_DIR="${ROOT_DIR}/terraform/environments/${ENV}"

# 1. Remove Helm releases
helm uninstall tfe          --namespace openshift-tfe 2>/dev/null || true
helm uninstall tfe-operator --namespace openshift-tfe 2>/dev/null || true

# 2. Remove OpenShift manifests
oc delete -f "${ROOT_DIR}/openshift/operators/" --ignore-not-found
oc delete -f "${ROOT_DIR}/openshift/namespaces/" --ignore-not-found

# 3. Terraform destroy
pushd "${ENV_DIR}" > /dev/null
terraform destroy -auto-approve
popd > /dev/null

echo "[✔] All resources destroyed"
