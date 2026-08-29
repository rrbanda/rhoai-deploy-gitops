# RHOAI 3.5 -- Helm Chart GitOps Deployment

Automated deployment of Red Hat OpenShift AI (RHOAI) 3.5 using Helm charts
managed through OpenShift GitOps (ArgoCD).

## Version Info

| Field | Value |
|-------|-------|
| Chart Version | v3.5.0 |
| Chart Digest | sha256:a449277180247b42488721025c37f8db76bc6e26a5dedfc3103fa7e5231b58eb |
| OCP Compatibility | 4.19+ |
| Branch | `helm-deploy-v3.5` |
| Previous Version | For RHOAI 3.4: switch to `helm-deploy-v3.4` |

## Quick Start

### 1. Bootstrap GitOps + Sealed Secrets

```bash
oc apply -k helm-deploy/bootstrap/
```

This installs:
- OpenShift GitOps operator (ArgoCD)
- Sealed Secrets operator
- ArgoCD cluster-admin RBAC

Wait for the GitOps operator to become ready:
```bash
oc wait --for=condition=Available deployment/openshift-gitops-server \
  -n openshift-gitops --timeout=300s
```

### 2. Deploy the ArgoCD Instance

```bash
oc apply -f helm-deploy/bootstrap/argocd-instance.yaml
```

### 3. Deploy RHOAI

**Full platform** (all components):
```bash
oc apply -f helm-deploy/applications/rhoai-platform.yaml
```

**Inference-only** (RHAII profile -- KServe only):
```bash
oc apply -f helm-deploy/applications/rhoai-inference.yaml
```

### 4. Monitor Progress

```bash
# Watch ArgoCD sync status
oc get application rhoai-platform -n openshift-gitops -w

# Check DataScienceCluster status
oc get datasciencecluster -A

# Check operator subscriptions
oc get subscriptions -A
```

## Upgrade from 3.4

1. Update `targetRevision` in your Application manifest:
   ```yaml
   source:
     targetRevision: helm-deploy-v3.5
   ```
2. ArgoCD will automatically sync the new chart version.
3. Monitor the rollout:
   ```bash
   oc get application -n openshift-gitops -w
   ```

## Disconnected / Air-Gapped Clusters

For clusters without access to `redhat-operators`, override the OLM catalog source:

```yaml
# In your values override:
olm:
  source: my-disconnected-catalog
  sourceNamespace: openshift-marketplace
```

Apply as a values file or inline in the ArgoCD Application:
```bash
helm template rhoai helm-deploy/chart/ \
  -f helm-deploy/values/full-platform.yaml \
  --set olm.source=my-disconnected-catalog \
  --skip-schema-validation
```

## Files

```
helm-deploy/
├── README.md                          # This file
├── bootstrap/
│   ├── kustomization.yaml             # Kustomize entry point
│   ├── gitops-operator-subscription.yaml
│   ├── sealed-secrets-subscription.yaml
│   ├── argocd-rbac.yaml
│   └── argocd-instance.yaml
├── applications/
│   ├── rhoai-platform.yaml            # Full platform ArgoCD Application
│   └── rhoai-inference.yaml           # Inference-only ArgoCD Application
├── chart/                             # RHOAI Helm chart (v3.5.0)
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values.schema.json
│   ├── profiles/
│   └── templates/
├── values/
│   ├── full-platform.yaml             # All components Managed
│   └── inference-only.yaml            # RHAII profile (KServe only)
└── sealed-secrets/
    ├── README.md
    └── registry-secret.yaml.template
```

## Troubleshooting

### ArgoCD sync fails with "CRD not found"

The chart uses `skipCrdCheck: true` and the sync option
`SkipDryRunOnMissingResource=true` to handle CRD ordering. If you still see
issues, ensure the RHOAI operator subscription has been processed first:

```bash
oc get csv -n redhat-ods-operator
```

### Operator stuck in "UpgradePending"

Check install plan approval:
```bash
oc get installplan -n redhat-ods-operator
```

If using `Manual` approval, approve the plan:
```bash
oc patch installplan <plan-name> -n redhat-ods-operator \
  --type merge -p '{"spec":{"approved":true}}'
```

### DataScienceCluster not progressing

Verify all dependency operators are healthy:
```bash
oc get csv -A | grep -E "(cert-manager|rhcl|kueue|lws|jobset)"
```

### Gateway not created

Ensure the `allowedRoutes.namespaces.from` is set (the chart requires this):
```bash
oc get gateway -n openshift-ingress
oc describe gatewayclass openshift-ai-inference
```

### Sync retry exhausted

The Application has retry backoff (30s base, factor 2, max 10m, 10 attempts).
If all retries are exhausted, check ArgoCD UI for the specific error and
manually trigger a sync after resolving the issue:
```bash
argocd app sync rhoai-platform
```
