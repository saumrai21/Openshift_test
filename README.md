# Terraform Enterprise on OpenShift (GCP) — One-Click Deployment

Deploy **Terraform Enterprise (TFE) v202501+** on **Red Hat OpenShift** running on **Google Cloud Platform** with a single command.

---

## Architecture Overview

```
GCP Project
├── VPC Network
│   ├── Private Subnet (OpenShift nodes)
│   └── Private Subnet (Cloud SQL / Redis)
├── GKE / OpenShift Cluster (OSD or ROSA-equivalent ARO)
│   ├── openshift-tfe namespace
│   │   ├── TFE Operator (HashiCorp)
│   │   ├── TFE StatefulSet (Active/Active or Single)
│   │   ├── TFE Ingress (OpenShift Route + cert-manager)
│   │   └── External Secrets (GCP Secret Manager)
│   └── Supporting Operators
│       ├── cert-manager
│       └── external-secrets
├── Cloud SQL (PostgreSQL 15)
├── Memorystore (Redis 7)
├── Cloud Storage (TFE blob storage)
└── Secret Manager (TFE license + credentials)
```

## Prerequisites

| Tool | Version |
|------|---------|
| `gcloud` CLI | >= 450.0 |
| `terraform` | >= 1.7.0 |
| `oc` (OpenShift CLI) | >= 4.14 |
| `helm` | >= 3.14 |
| `kubectl` | >= 1.28 |

---

## Quick Start — One-Click Deploy

```bash
# 1. Clone the repo
git clone https://github.com/your-org/tfe-openshift-gcp.git
cd tfe-openshift-gcp

# 2. Copy and fill in your variables
cp terraform/environments/prod/terraform.tfvars.example \
   terraform/environments/prod/terraform.tfvars

# 3. Place your TFE license file
cp /path/to/terraform.hclic ./terraform.hclic

# 4. Run the one-click deploy script
./scripts/deploy.sh --env prod
```

The script will:
1. Authenticate to GCP and validate quotas
2. Provision GCP infrastructure (VPC, Cloud SQL, Redis, GCS, Secrets)
3. Install / configure OpenShift via Terraform
4. Deploy TFE Operator + TFE instance via Helm
5. Run smoke tests and print the TFE URL

---

## Configuration

### `terraform/environments/prod/terraform.tfvars.example`

```hcl
# GCP
project_id       = "my-gcp-project"
region           = "us-central1"
zone             = "us-central1-a"

# OpenShift
ocp_cluster_name    = "tfe-ocp"
ocp_version         = "4.14"
node_machine_type   = "n2-standard-8"
node_count          = 3

# TFE
tfe_hostname        = "tfe.example.com"
tfe_version         = "v202501-1"   # set to "latest" for auto-resolve
tfe_license_secret  = "tfe-license" # name in GCP Secret Manager
tfe_encryption_password_secret = "tfe-enc-password"
tfe_replicas        = 2             # 1 = single node, 2+ = active/active

# Database
db_tier             = "db-custom-4-15360"
db_version          = "POSTGRES_15"

# Redis
redis_tier          = "STANDARD_HA"
redis_memory_gb     = 4
```

---

## Repo Structure

```
.
├── README.md
├── scripts/
│   ├── deploy.sh           # One-click deploy entrypoint
│   ├── destroy.sh          # Tear-down script
│   ├── preflight.sh        # Prerequisite checks
│   └── smoke-test.sh       # Post-deploy validation
├── terraform/
│   ├── modules/
│   │   ├── gcp-infra/      # VPC, Cloud SQL, Redis, GCS, IAM, Secrets
│   │   ├── openshift/      # OpenShift cluster provisioning
│   │   └── tfe/            # TFE Operator + Helm release
│   └── environments/
│       ├── dev/
│       └── prod/
├── openshift/
│   ├── namespaces/         # Namespace + SCC configs
│   ├── operators/          # OperatorGroup + Subscriptions
│   └── storage/            # StorageClass definitions
├── helm/
│   └── tfe-chart/          # TFE Helm chart (values + templates)
└── docs/
    ├── architecture.md
    ├── upgrade.md
    └── troubleshooting.md
```

---

## Upgrading TFE

See [docs/upgrade.md](docs/upgrade.md) for zero-downtime upgrade instructions.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md).

## License

Apache 2.0
