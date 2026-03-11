# Upgrading Terraform Enterprise

## Zero-Downtime Rolling Upgrade (Active/Active)

TFE supports rolling upgrades when running in active/active mode with 2+ replicas.

### Steps

1. **Check current version**
   ```bash
   curl -s https://YOUR_TFE_HOST/api/v2/meta/versions \
     -H "Authorization: Bearer $TFE_TOKEN" | jq '.data.current_version'
   ```

2. **Review release notes**
   Always check [HashiCorp TFE releases](https://developer.hashicorp.com/terraform/enterprise/releases)
   before upgrading. Note any required sequential upgrade steps.

3. **Update the version in tfvars**
   ```hcl
   tfe_version = "v202503-1"  # New target version
   ```

4. **Run the upgrade**
   ```bash
   ./scripts/deploy.sh --env prod --skip-infra
   ```
   This re-runs only the Helm/TFE deployment step, triggering a rolling update.

5. **Monitor the rollout**
   ```bash
   kubectl rollout status statefulset/tfe -n openshift-tfe --timeout=10m
   kubectl get pods -n openshift-tfe -w
   ```

6. **Verify health**
   ```bash
   ./scripts/smoke-test.sh --env prod
   ```

## Sequential Upgrade Path

Some TFE versions require upgrading through intermediate releases.
For example, to upgrade from v202410 to v202501, you may need to go through v202412.

Always consult the [upgrade path documentation](https://developer.hashicorp.com/terraform/enterprise/releases/upgrade-path).

## Rollback

If a new version has issues:

```bash
# Roll back Helm release to previous revision
helm rollback tfe 0 --namespace openshift-tfe --wait

# Or set an explicit previous version in tfvars and redeploy
tfe_version = "v202412-1"
./scripts/deploy.sh --env prod --skip-infra
```

## Database Migrations

TFE automatically runs database migrations on startup. Ensure Cloud SQL backups
are current before any upgrade (automated daily backups are configured by default).
