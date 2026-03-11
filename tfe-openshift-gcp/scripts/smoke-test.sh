#!/usr/bin/env bash
# smoke-test.sh — Post-deploy validation for TFE on OpenShift/GCP
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV="prod"

while [[ $# -gt 0 ]]; do
  case $1 in --env) ENV="$2"; shift 2 ;; *) shift ;; esac
done

TFVARS="${ROOT_DIR}/terraform/environments/${ENV}/terraform.tfvars"
TFE_HOST=$(grep 'tfe_hostname' "${TFVARS}" | awk -F'"' '{print $2}')
PASS=0; FAIL=0

check() {
  local desc=$1; shift
  if "$@" &>/dev/null; then
    echo -e "\033[0;32m[✔]\033[0m ${desc}"
    ((PASS++)) || true
  else
    echo -e "\033[0;31m[✘]\033[0m ${desc}"
    ((FAIL++)) || true
  fi
}

echo "═════════════════════════════════════"
echo "  TFE Smoke Tests — ${TFE_HOST}"
echo "═════════════════════════════════════"

# Pod checks
check "TFE pods running" \
  kubectl get pods -n openshift-tfe -l app=terraform-enterprise \
    --field-selector=status.phase=Running --no-headers

check "TFE operator running" \
  kubectl get pods -n openshift-tfe -l app=tfe-operator \
    --field-selector=status.phase=Running --no-headers

# HTTP checks (wait up to 3 min for TFE to be ready)
echo "Waiting for TFE HTTP endpoint..."
for i in $(seq 1 18); do
  if curl -fsSL --max-time 10 "https://${TFE_HOST}/api/v2/ping" -o /dev/null 2>/dev/null; then
    break
  fi
  echo "  Attempt ${i}/18 — waiting 10s..."
  sleep 10
done

check "TFE /api/v2/ping returns 200" \
  curl -fsSL --max-time 15 "https://${TFE_HOST}/api/v2/ping" -o /dev/null

check "TFE healthcheck endpoint" \
  bash -c "curl -fsSL --max-time 15 'https://${TFE_HOST}/_health_check' | grep -q 'ok'"

check "TFE version API accessible" \
  bash -c "curl -fsSL --max-time 15 'https://${TFE_HOST}/api/v2/meta/versions' | jq -e '.data' >/dev/null"

# TLS check
check "Valid TLS certificate" \
  bash -c "echo | openssl s_client -connect '${TFE_HOST}:443' -servername '${TFE_HOST}' 2>/dev/null | openssl x509 -noout -checkend 0"

# Route check
check "OpenShift Route exists" \
  oc get route tfe -n openshift-tfe

# Storage check
check "PVCs bound" \
  bash -c "kubectl get pvc -n openshift-tfe --no-headers | grep -v 'Bound' | wc -l | grep -q '^0$'"

echo ""
echo "─────────────────────────────────────"
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "─────────────────────────────────────"
[[ ${FAIL} -eq 0 ]] && echo -e "\033[0;32m✔ All smoke tests passed!\033[0m" || \
  { echo -e "\033[0;31m✘ Some tests failed — check logs\033[0m"; exit 1; }
