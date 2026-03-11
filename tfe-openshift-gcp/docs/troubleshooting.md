# Troubleshooting

## Common Issues

### TFE pods stuck in `Pending`
```bash
kubectl describe pod -n openshift-tfe -l app=terraform-enterprise
```
- **PVC not bound**: Check StorageClass `tfe-ssd` exists and CSI driver is enabled
- **Node taint mismatch**: Verify nodes have `workload=tfe` label
- **Resource quota exceeded**: Check namespace quotas with `oc describe quota -n openshift-tfe`

### TFE pods in `CrashLoopBackOff`
```bash
kubectl logs -n openshift-tfe -l app=terraform-enterprise --previous
```
- **DB connection failure**: Verify Cloud SQL private IP, password in secret, and VPC peering
- **License invalid**: Re-upload license: `gcloud secrets versions add tfe-license --data-file=terraform.hclic`
- **Redis unreachable**: Test with `kubectl run redis-test --image=redis:7 -n openshift-tfe --rm -it -- redis-cli -h REDIS_HOST ping`

### Route not accessible
```bash
oc get route tfe -n openshift-tfe
oc describe route tfe -n openshift-tfe
```
- Check TLS certificate is issued: `kubectl get cert -n openshift-tfe`
- Check DNS: `nslookup tfe.example.com` should resolve to the cluster ingress IP

### Terraform runs failing (workspace agents)
- Verify the TFE pod has IAM permissions: `gcloud projects get-iam-policy PROJECT_ID --filter="bindings.members:tfe-sa"`
- Check GCS bucket access from within a pod

### Workload Identity not working
```bash
kubectl run wi-test \
  --image=google/cloud-sdk:slim \
  --serviceaccount=tfe \
  --namespace=openshift-tfe \
  --rm -it -- gcloud auth print-access-token
```
- Verify the `iam.gke.io/gcp-service-account` annotation on the Kubernetes SA matches the GCP SA email

## Useful Commands

```bash
# Stream TFE logs
kubectl logs -f statefulset/tfe -n openshift-tfe

# Get TFE admin token
kubectl exec -n openshift-tfe statefulset/tfe -- \
  tfectl admin token

# Check TFE system info
curl -s https://TFE_HOST/_health_check

# Restart TFE (rolling)
kubectl rollout restart statefulset/tfe -n openshift-tfe

# List all TFE resources
kubectl get all -n openshift-tfe
```
