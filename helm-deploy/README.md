# RHOAI 3.4 -- Helm Chart GitOps Deployment

Deploy Red Hat OpenShift AI **3.4** using the official Helm chart managed by
OpenShift GitOps (ArgoCD). The chart is committed to this branch -- ArgoCD
reads it directly from Git with no OCI registry auth needed at deploy time.

| | Details |
|---|---|
| **RHOAI version** | 3.4 (chart v3.4.0, appVersion v3.4.0) |
| **Chart source** | `oci://registry.redhat.io/rhai/rhai-on-openshift-chart:v3.4` |
| **Chart digest** | `sha256:438f4d4e74de9b97f5a2e86e455de491e61b816d6b5294a765b1e611d9995838` |
| **OCP requirement** | 4.19+ |
| **Branch** | `helm-deploy-v3.4` |
| **For RHOAI 3.4** | Switch to branch `helm-deploy-v3.4` |

## Deployment Architecture

```
oc apply -f app-of-apps.yaml
    |
    +-- Wave 0: Service Mesh 3.x operator (prerequisite for Llama Stack)
    |       Subscription in openshift-operators
    |
    +-- Wave 1: RHOAI platform (Helm chart)
    |       All operators + DSC + DSCI + Gateways
    |
    +-- PostSync: Kuadrant controller restart
            Fixes known AuthPolicy enforcement timing issue
```

## Quick Start (Connected)

### 1. Bootstrap (one-time)

```bash
oc apply -k helm-deploy/bootstrap/

until oc apply -f helm-deploy/bootstrap/argocd-instance.yaml; do sleep 10; done

oc wait --for=condition=Available deployment/openshift-gitops-server \
  -n openshift-gitops --timeout=300s
```

### 2. Deploy RHOAI 3.4

**Option A -- App-of-Apps (recommended):**

Deploys Service Mesh 3.x first (wave 0), then the RHOAI platform (wave 1):

```bash
oc apply -f helm-deploy/applications/app-of-apps.yaml
```

**Option B -- Direct (if Service Mesh 3.x is already installed):**

```bash
# Full platform
oc apply -f helm-deploy/applications/rhoai-platform.yaml
# OR inference only
oc apply -f helm-deploy/applications/rhoai-inference.yaml
```

### 3. Monitor

```bash
oc get application -n openshift-gitops -w
oc get csv -A | grep -E "(rhods|servicemesh|cert-manager|rhcl|kueue)"
oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'
```

## Disconnected Deployment

### 1. Mirror images (from a connected machine)

Use the provided ImageSetConfiguration to mirror all operators:

```bash
# Edit imageset-config-template.yaml:
#   Replace REPLACE_OCP_VERSION with v4.19
#   Replace REPLACE_RHOAI_CHANNEL with stable-3.4
#   Replace REPLACE_KUEUE_CHANNEL with stable-v1.2

oc-mirror --config helm-deploy/imageset-config-template.yaml \
  docker://<mirror-registry> --v2
```

### 2. Apply generated mirror config

```bash
oc apply -f working-dir/cluster-resources/  # IDMS, CatalogSource
```

Note the generated CatalogSource name (e.g., `cs-redhat-operator-index-v4-19`).

### 3. Update disconnected overlay

Edit `helm-deploy/prerequisites/servicemesh/overlays/disconnected/kustomization.yaml`:

```yaml
value: cs-redhat-operator-index-v4-19  # your catalog name
```

### 4. Deploy with disconnected Applications

```bash
# Use the disconnected SM3 application
oc apply -f helm-deploy/applications/00-servicemesh-disconnected.yaml

# Use the disconnected platform application
oc apply -f helm-deploy/applications/rhoai-platform-disconnected.yaml
```

The disconnected Application variants set `olm.source` to your mirrored catalog
so all Helm-chart-managed operator Subscriptions use the correct source.

## Service Mesh 3.x Dependency

Service Mesh 3.x (Sail Operator) is required for:
- **Llama Stack/Llama Stack** workloads (RAG, agentic AI)
- **KServe** gateway infrastructure (Istio control plane for Gateway API)

The SM3 operator must be installed **before** the RHOAI operator. The App-of-Apps
pattern handles this automatically via sync waves.

### Known issue: Kuadrant AuthPolicy not enforced

The RHCL (Kuadrant) operator starts before its dependencies (Istio, Limitador)
are fully available. It caches "MissingDependency" and never enforces AuthPolicy.
The PostSync hook Job (`prerequisites/kuadrant-restart/job.yaml`) automatically
restarts the Kuadrant controller after the DSC reaches Ready.

## Files

```
helm-deploy/
├── chart/                                  # Official RHOAI 3.4 Helm chart (unmodified)
├── bootstrap/                              # GitOps + Sealed Secrets + ArgoCD instance
├── prerequisites/
│   ├── servicemesh/
│   │   ├── base/                           # SM3 Subscription (connected)
│   │   └── overlays/disconnected/          # SM3 with mirrored catalog
│   └── kuadrant-restart/                   # PostSync Job for Kuadrant fix
├── applications/
│   ├── app-of-apps.yaml                    # Entry point (deploys all child apps)
│   ├── 00-servicemesh.yaml                 # Wave 0: SM3 (connected)
│   ├── 00-servicemesh-disconnected.yaml    # Wave 0: SM3 (disconnected)
│   ├── rhoai-platform.yaml                 # Wave 1: Full platform (connected)
│   ├── rhoai-platform-disconnected.yaml    # Wave 1: Full platform (disconnected)
│   ├── rhoai-inference.yaml                # Wave 1: Inference only (connected)
│   └── rhoai-inference-disconnected.yaml   # Wave 1: Inference only (disconnected)
├── values/                                 # Standalone values files
├── sealed-secrets/                         # Optional secret management
└── imageset-config-template.yaml           # Mirror config for disconnected
```

## Upgrading from 3.4 to 3.4

Change `targetRevision` in your Application (or app-of-apps):

```yaml
targetRevision: helm-deploy-v3.4
```

## Troubleshooting

**SM3 operator not installing**: Check `oc get sub servicemeshoperator3 -n openshift-operators -o yaml`.

**CRs not created**: Expected on first sync. ArgoCD retries (limit=10, 30s backoff).

**AuthPolicy not enforced**: The PostSync hook should handle this. If not, manually:
```bash
oc delete pod -n kuadrant-system -l control-plane=controller-manager
```

**Force re-sync**:
```bash
oc annotate application rhoai-platform -n openshift-gitops \
  argocd.argoproj.io/refresh=hard --overwrite
```
