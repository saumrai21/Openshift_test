#!/usr/bin/env bash
# preflight.sh — validate all prerequisites before deployment
set -euo pipefail

PASS=0; FAIL=0
ok()   { echo -e "\033[0;32m[✔]\033[0m $*"; ((PASS++)) || true; }
fail() { echo -e "\033[0;31m[✘]\033[0m $*"; ((FAIL++)) || true; }
warn() { echo -e "\033[1;33m[⚠]\033[0m $*"; }

check_cmd() {
  local cmd=$1 min_ver=$2
  if command -v "${cmd}" &>/dev/null; then
    ok "${cmd} found: $(${cmd} version 2>/dev/null | head -1 || echo 'ok')"
  else
    fail "${cmd} not found — install it before deploying (min version: ${min_ver})"
  fi
}

echo "═══════════════════════════════════════"
echo "  TFE/OpenShift/GCP Preflight Checks"
echo "═══════════════════════════════════════"

# Required binaries
check_cmd terraform "1.7.0"
check_cmd gcloud    "450.0"
check_cmd oc        "4.14"
check_cmd kubectl   "1.28"
check_cmd helm      "3.14"
check_cmd jq        "1.6"
check_cmd openssl   "3.0"

# Terraform version check
TF_VER=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' || echo "0.0.0")
IFS='.' read -ra TF_PARTS <<< "${TF_VER}"
if [[ ${TF_PARTS[0]} -ge 1 && ${TF_PARTS[1]} -ge 7 ]]; then
  ok "Terraform version ${TF_VER} meets minimum (1.7.0)"
else
  fail "Terraform ${TF_VER} is below minimum 1.7.0"
fi

# GCP auth
if gcloud auth print-access-token &>/dev/null; then
  ok "GCP credentials active"
else
  warn "No active GCP credentials — deploy.sh will prompt for login"
fi

# License file
if [[ -f "$(git rev-parse --show-toplevel 2>/dev/null)/terraform.hclic" ]]; then
  ok "terraform.hclic license file found"
else
  fail "terraform.hclic not found in repo root — required for TFE deployment"
fi

# Summary
echo ""
echo "─────────────────────────────────────────"
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "─────────────────────────────────────────"
[[ ${FAIL} -eq 0 ]] || exit 1
