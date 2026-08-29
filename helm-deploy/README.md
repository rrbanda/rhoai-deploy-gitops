# RHOAI 3.5 -- GitOps Deployment with Helm Chart

Deploy Red Hat OpenShift AI **3.5** on OpenShift using the official Helm chart,
managed entirely through OpenShift GitOps (ArgoCD). The chart is committed to
this branch -- ArgoCD reads it directly from Git. No OCI registry auth needed
at deploy time.

| | Details |
|---|---|
| **RHOAI version** | 3.5 (chart v3.5.0, appVersion v3.5.0) |
| **Chart source** | `oci://registry.redhat.io/rhai/rhai-on-openshift-chart:v3.5` |
| **Chart digest** | `sha256:a449277180247b42488721025c37f8db76bc6e26a5dedfc3103fa7e5231b58eb` |
| **OCP requirement** | 4.19+ |
| **Branch** | `helm-deploy-v3.5` |
| **For RHOAI 3.4** | Switch to branch `helm-deploy-v3.4` |

---

## Architecture

The deployment is organized into three layers, each an ArgoCD Application
with sync-wave ordering:

```
oc apply -f helm-deploy/app-of-apps.yaml
    |
    +-- Wave 0: Service Mesh 3.x operator
    |       OLM Subscription in openshift-operators
    |       Required before RHOAI for OGX/KServe gateway
    |
    +-- Wave 1: RHOAI platform (Helm chart)
    |       11 operator Subscriptions + DSC + DSCI + Gateways
    |       All components: KServe, AIPipelines, Dashboard, Kueue,
    |       Ray, Trainer, Workbenches, ModelRegistry, MLflow, OGX, etc.
    |
    +-- Wave 2: AutoRAG workload
            OGXServer + Milvus + Pipeline Server (DSPA)
            Self-contained RAG stack in its own namespace
```

### What each layer deploys

| Layer | ArgoCD Application | Resources | Source |
|---|---|---|---|
| **Prerequisites** | `rhoai-servicemesh` (wave 0) | 1 OLM Subscription | Kustomize: `prerequisites/servicemesh/base/` |
| **Platform** | `rhoai-platform` (wave 1) | ~43 resources (11 operators, DSC, DSCI, Gateways, dependency CRs) | Helm chart: `chart/` |
| **Workload** | `autorag-workload` (wave 2) | ~10 resources (OGXServer, DSPA, Milvus, etcd, SealedSecrets) | Kustomize: `workloads/autorag/` |
| **Parent** | `rhoai-deploy` | Discovers child Applications in `applications/` | Directory: `applications/` |

### What the Helm chart provides (DO NOT duplicate)

The official Helm chart (`chart/`) handles all operator lifecycle:

- 11 OLM Subscriptions: rhods-operator, cert-manager, RHCL/Kuadrant, Kueue, JobSet, LeaderWorkerSet, CMA, NFD, GPU Operator, Cluster Observability, OpenTelemetry, Tempo
- DataScienceCluster (DSC) with all 15 components + sub-components:
  - KServe (with NIM, WVA, raw deployment)
  - AI Gateway (MaaS + BatchGateway)
  - AIPipelines (with Argo Workflows Controllers)
  - SparkOperator
  - All others: Dashboard, Kueue, Ray, Trainer, TrainingOperator, Workbenches, ModelRegistry, TrustyAI, MLflow, FeastOperator, OGX
- DSCInitialization (DSCI) with monitoring config
- Authorino TLS enabled via `dependencies.rhcl.config.tlsEnabled: true`
- GatewayClass + Gateway for KServe and MaaS inference
- Dependency CRs: Kuadrant, Kueue, LeaderWorkerSetOperator, JobSetOperator
- Tri-state dependency resolution (`auto`/`true`/`false`)

### What the workload layer adds (separate from chart)

The workload layer (`workloads/autorag/`) deploys instances of CRDs the
chart installed -- not operators or subscriptions:

- `autorag` namespace with `opendatahub.io/dashboard: "true"` label
- OGXServer instance (RAG backbone: inference, embedding, vector I/O, file processing)
- Milvus standalone + etcd (vector database for RAG)
- DataSciencePipelinesApplication with built-in MinIO and AutoRAG enabled
- SealedSecrets for LLM API key (encrypted, safe in Git)
- User Workload Monitoring ConfigMap (required for MaaS metrics)

---

## Prerequisites

| Requirement | Details |
|---|---|
| OpenShift | 4.19+ with cluster-admin access |
| `oc` CLI | Installed and authenticated |
| `kubeseal` CLI | For encrypting workload secrets (install: `brew install kubeseal`) |
| Helm | 3.17+ (optional, for local `helm template` testing) |

---

## Quick Start (Connected)

### Step 1: Bootstrap (one-time)

Install the OpenShift GitOps operator, Sealed Secrets operator, and RBAC:

```bash
oc apply -k helm-deploy/bootstrap/
```

Wait for the GitOps operator to create the ArgoCD CRD, then apply the
ArgoCD instance:

```bash
until oc apply -f helm-deploy/bootstrap/argocd-instance.yaml; do sleep 10; done
```

Wait for ArgoCD to be ready:

```bash
oc wait --for=condition=Available deployment/openshift-gitops-server \
  -n openshift-gitops --timeout=300s
```

### Step 2: Wire RHACM (if installed)

If the cluster has Red Hat Advanced Cluster Management:

```bash
oc apply -k helm-deploy/rhacm/
```

This creates:
- **ManagedClusterSetBinding** -- binds the default cluster set to `openshift-gitops`
- **Placement** -- selects `local-cluster` (the hub)
- **GitOpsCluster** -- registers the cluster in ArgoCD via RHACM

Skip this step if RHACM is not installed. ArgoCD works standalone.

### Step 3: Seal workload secrets

The AutoRAG workload needs an LLM API key. Seal it with your cluster's
Sealed Secrets certificate:

```bash
# Wait for Sealed Secrets controller
oc wait --for=condition=Available deployment/sealed-secrets-controller \
  -n sealed-secrets --timeout=120s

# Copy the template and fill in your LLM API key
cp helm-deploy/workloads/autorag/templates/llm-api-secret.yaml.template /tmp/llm-secret.yaml
# Edit /tmp/llm-secret.yaml: replace REPLACE_WITH_LLM_API_KEY

# Fetch the cluster's sealing certificate
kubeseal --fetch-cert --controller-namespace sealed-secrets > /tmp/pub-cert.pem

# Seal
kubeseal --format yaml --cert /tmp/pub-cert.pem \
  < /tmp/llm-secret.yaml \
  > helm-deploy/workloads/autorag/sealed-llm-api-secret.yaml

# Commit the sealed version (safe in Git)
git add helm-deploy/workloads/autorag/sealed-llm-api-secret.yaml
git commit -m "Seal LLM API key for AutoRAG workload"
git push

# Clean up plaintext
rm /tmp/llm-secret.yaml /tmp/pub-cert.pem
```

SealedSecrets are **cluster-specific** -- the encrypted data can only be
decrypted by the Sealed Secrets controller on the cluster where you ran
`kubeseal --fetch-cert`. When deploying to a different cluster, re-seal.

### Step 4: Deploy

```bash
oc apply -f helm-deploy/app-of-apps.yaml
```

ArgoCD discovers all Applications in `applications/` and deploys them
in wave order:

1. **Wave 0**: Service Mesh 3.x operator installs (1-2 min)
2. **Wave 1**: Helm chart renders all RHOAI operators + DSC (ArgoCD retries
   until CRDs exist, ~5-10 min for all operators to reach Succeeded)
3. **Wave 2**: AutoRAG workload deploys (Milvus, DSPA, OGXServer)

DSC takes ~15-30 minutes to fully reconcile all 22 components.

### Step 5: Verify

```bash
# ArgoCD Applications
oc get applications.argoproj.io -n openshift-gitops

# DSC phase
oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'

# Operator CSVs
oc get csv -A | grep -E "(rhods|servicemesh|cert-manager|rhcl|kueue)"

# AutoRAG workload pods
oc get pods -n autorag
```

Expected: 4 Applications Synced+Healthy, DSC phase Ready, ~11 pods in `autorag`.

### Step 6: Enable Authorino TLS (optional, for production)

After the Kuadrant operator creates the Authorino service:

```bash
oc annotate svc/authorino-authorino-authorization \
  service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
  -n kuadrant-system
```

---

## Developer Endpoints

After deployment, these endpoints are available for building RAG applications:

### OGX Server (RAG backbone -- OpenAI-compatible API)

| | Value |
|---|---|
| **Internal URL** | `http://autorag-ogx-service.autorag.svc:8321` |
| **Port** | 8321 (API), 9464 (metrics) |
| **API format** | OpenAI-compatible |

```bash
# List models
curl http://autorag-ogx-service.autorag.svc:8321/v1/models

# Chat completion
curl -X POST http://autorag-ogx-service.autorag.svc:8321/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "gemini/models/gemini-2.5-flash", "messages": [{"role": "user", "content": "What is RAG?"}]}'

# Embeddings
curl -X POST http://autorag-ogx-service.autorag.svc:8321/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model": "sentence-transformers/nomic-ai/nomic-embed-text-v1.5", "input": "text to embed"}'
```

### Available models (default config)

| Type | Model ID | Provider |
|---|---|---|
| Embedding | `sentence-transformers/nomic-ai/nomic-embed-text-v1.5` | Local (CPU) |
| Reranker | `sentence-transformers/Qwen/Qwen3-Reranker-0.6B` | Local (CPU) |
| LLM | `gemini/models/gemini-2.5-flash` | Gemini API |
| LLM | `gemini/models/gemini-2.5-pro` | Gemini API |

### Milvus vector database

| | Value |
|---|---|
| **Internal URL** | `http://milvus-service.autorag.svc:19530` |
| **Ports** | 19530 (gRPC/REST), 9091 (metrics) |

### Other endpoints

| Service | URL |
|---|---|
| RHOAI Dashboard | `https://rhods-dashboard-redhat-ods-applications.apps.<cluster-domain>` |
| AutoRAG UI | Dashboard > Gen AI Studio > AutoRAG |
| KServe Inference Gateway | Check: `oc get gateway openshift-ai-inference -n openshift-ingress` |
| MaaS Gateway | Check: `oc get gateway maas-default-gateway -n openshift-ingress` |
| ArgoCD Console | `oc get route openshift-gitops-server -n openshift-gitops` |

### Local development (port-forwarding)

```bash
oc port-forward svc/autorag-ogx-service -n autorag 8321:8321 &
oc port-forward svc/milvus-service -n autorag 19530:19530 &
# Use http://localhost:8321 and http://localhost:19530
```

---

## Deployment Profiles

The `applications/` directory controls what gets deployed. To switch profiles,
copy a file from `profiles/` into `applications/`, commit, and push.

| Profile | How to activate | Components |
|---|---|---|
| **Full platform** (default) | Already in `applications/rhoai-platform.yaml` | All 15 DSC components |
| **Inference only** | `cp profiles/rhoai-inference.yaml applications/rhoai-platform.yaml` | KServe + dependencies only |
| **Disconnected** | `cp profiles/rhoai-platform-disconnected.yaml applications/rhoai-platform.yaml` | Full platform with mirrored catalog |

---

## Disconnected Deployment

### 1. Mirror images

```bash
# Edit imageset-config-template.yaml:
#   REPLACE_OCP_VERSION -> v4.19
#   REPLACE_RHOAI_CHANNEL -> stable-3.5
#   REPLACE_KUEUE_CHANNEL -> stable-v1.4

oc-mirror --config helm-deploy/imageset-config-template.yaml \
  docker://<mirror-registry> --v2
```

### 2. Apply mirror config

```bash
oc apply -f working-dir/cluster-resources/  # IDMS, CatalogSource
```

Note the generated CatalogSource name (e.g., `cs-redhat-operator-index-v4-19`).

### 3. Swap to disconnected profiles

```bash
cp profiles/00-servicemesh-disconnected.yaml applications/00-servicemesh.yaml
cp profiles/rhoai-platform-disconnected.yaml applications/rhoai-platform.yaml
```

Edit both: replace `REPLACE_WITH_MIRRORED_CATALOG_NAME` with your catalog name.

Edit `prerequisites/servicemesh/overlays/disconnected/kustomization.yaml` with
the same catalog name.

Commit, push, apply app-of-apps.

---

## Upgrading

### From 3.4 to 3.5

Change `targetRevision` in your Application (or app-of-apps):

```yaml
targetRevision: helm-deploy-v3.5  # was: helm-deploy-v3.4
```

### Updating the chart

```bash
helm registry login registry.redhat.io
helm pull oci://registry.redhat.io/rhai/rhai-on-openshift-chart \
  --version v3.6 --untar --untardir /tmp/upgrade
rm -rf helm-deploy/chart
mv /tmp/upgrade/rhai-on-openshift-chart helm-deploy/chart
# Review values.yaml for new components, commit, push
```

---

## Technical Notes

Critical details discovered during live deployment testing:

### OGX ConfigMap requires watch label

The OGX operator uses a label-selector informer. ConfigMaps referenced by
`overrideConfig` MUST have these labels or the operator cannot find them:

```yaml
metadata:
  labels:
    app: ogx
    ogx.io/watch: "true"
```

Without these labels, OGXServer fails with:
`failed to find referenced ConfigMap <namespace>/<name>`

### DSPA API version is v1

The DataSciencePipelinesApplication CRD uses `v1`, not `v1alpha1`:

```yaml
apiVersion: datasciencepipelinesapplications.opendatahub.io/v1
```

### DSPA requires explicit MinIO image

The DSPA CRD schema requires `spec.objectStorage.minio.image` when
`minio.deploy: true`. Omitting it causes a validation error:
`spec.objectStorage.minio.image: Required value`

```yaml
minio:
  deploy: true
  image: "quay.io/minio/minio:RELEASE.2023-09-04T19-57-37Z"
```

Note: the image is `quay.io/minio/minio` (official), NOT `quay.io/opendatahub/minio`.

### Milvus requires standalone env vars

Milvus standalone on OpenShift needs these environment variables:

```yaml
env:
  - name: DEPLOY_MODE
    value: standalone
  - name: ETCD_ENDPOINTS
    value: etcd-service.<namespace>.svc:2379
  - name: COMMON_STORAGETYPE
    value: local
```

### SealedSecrets are cluster-specific

Each cluster has a unique sealing key pair. A SealedSecret encrypted on
cluster A cannot be decrypted on cluster B. When deploying to a new cluster:

1. Fetch that cluster's cert: `kubeseal --fetch-cert --controller-namespace sealed-secrets`
2. Re-seal all secrets with the new cert
3. Commit and push the new sealed files

### Helm chart sets DISABLE_DSC_CONFIG=true

The chart adds `DISABLE_DSC_CONFIG=true` as an env var on the rhods-operator
Subscription. This prevents the operator from auto-creating a default DSC --
the chart manages the DSC directly.

### ArgoCD sync options explained

| Option | Why |
|---|---|
| `skipCrdCheck: true` | ArgoCD renders templates without cluster access; `lookup` always returns empty |
| `SkipDryRunOnMissingResource=true` | CRs fail dry-run if CRDs don't exist yet |
| `ServerSideApply=true` | Avoids field ownership conflicts with operators |
| `skipSchemaValidation: true` | v3.4 chart schema requires all managementState fields even when using profiles |

---

## Known Issues

### On clusters with prior RHOAI installations

**Stuck Kserve finalizer**: If a previous RHOAI was removed but component CRs
remain with finalizers, the new DSC can't reconcile KServe. Fix:

```bash
oc patch kserve default-kserve --type merge -p '{"metadata":{"finalizers":null}}'
```

### Duplicate Sealed Secrets controllers

If the cluster has a pre-existing Sealed Secrets controller (e.g., from another
project), both controllers try to decrypt every SealedSecret. One succeeds, the
other fails, causing ArgoCD to show "Degraded" even though the secret works.
Fix: stop the extra controller or seal with the correct controller's cert.

### OGX SCC race condition

On first deploy, the OGXServer creates a RoleBinding for `anyuid` SCC, but the
pod may attempt creation before the RoleBinding is ready. The pod fails with
"unable to validate against any security context constraint." ArgoCD's selfHeal
recreates the pod after the RoleBinding exists, resolving it automatically.

### ArgoCD sync stuck

If a sync operation gets stuck (e.g., namespace was terminating), clear it:

```bash
oc patch applications.argoproj.io <app-name> -n openshift-gitops \
  --type json -p '[{"op": "remove", "path": "/operation"}]'
```

---

## Troubleshooting

**All apps OutOfSync after deploy**: Expected on first sync. ArgoCD retries
(limit=10, 30s backoff). Operators need 2-5 min to register CRDs.

**DSC stuck in "Not Ready"**: Check which module is not ready:

```bash
oc get datasciencecluster default-dsc -o jsonpath='{range .status.conditions[?(@.status=="False")]}{.type}: {.reason} - {.message}{"\n"}{end}' | grep -v Removed
```

**OGXServer shows "Failed"**: Check if the ConfigMap has the required labels:

```bash
oc get configmap <name> -n <namespace> -o jsonpath='{.metadata.labels}'
# Must include: app=ogx and ogx.io/watch=true
```

**SealedSecret "Degraded" but Secret exists**: Likely a duplicate controller.
Check: `oc get pods -A -l app.kubernetes.io/name=sealed-secrets`

**Force re-sync**:

```bash
oc annotate applications.argoproj.io <app-name> -n openshift-gitops \
  argocd.argoproj.io/refresh=hard --overwrite
```

**ArgoCD admin password**:

```bash
oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d
```

---

## File Structure

```
helm-deploy/
├── app-of-apps.yaml                        # Entry point (apply this)
├── applications/                            # Auto-discovered by app-of-apps
│   ├── 00-servicemesh.yaml                 # Wave 0: SM3 operator
│   ├── rhoai-platform.yaml                 # Wave 1: RHOAI Helm chart
│   └── 02-autorag-workload.yaml            # Wave 2: AutoRAG stack
├── chart/                                   # Official RHOAI 3.5 Helm chart (unmodified, 33 files)
├── bootstrap/                               # One-time setup
│   ├── kustomization.yaml
│   ├── gitops-operator-subscription.yaml   # OpenShift GitOps operator
│   ├── sealed-secrets-subscription.yaml    # Sealed Secrets operator
│   ├── argocd-instance.yaml               # ArgoCD with custom health checks
│   └── argocd-rbac.yaml                   # cluster-admin for ArgoCD SA
├── rhacm/                                   # RHACM integration (optional)
│   ├── managedclustersetbinding.yaml
│   ├── placement.yaml
│   ├── gitopscluster.yaml
│   └── kustomization.yaml
├── prerequisites/
│   ├── servicemesh/
│   │   ├── base/                           # SM3 Subscription (connected)
│   │   └── overlays/disconnected/          # SM3 with mirrored catalog
│   └── kuadrant-restart/                   # PostSync Job (Kuadrant timing fix)
├── workloads/autorag/                       # AutoRAG workload layer
│   ├── kustomization.yaml
│   ├── namespace.yaml                      # autorag namespace
│   ├── milvus.yaml                         # Milvus standalone + etcd
│   ├── dspa.yaml                           # Pipeline server with built-in MinIO
│   ├── ogxserver.yaml                      # OGX instance
│   ├── ogx-config.yaml                    # OGX config (labeled with ogx.io/watch)
│   ├── sealed-llm-api-secret.yaml         # LLM API key (encrypted)
│   ├── sealed-s3-connection-secret.yaml   # S3 creds (encrypted, optional)
│   └── templates/                          # Plaintext templates (.gitignored)
├── profiles/                                # Alternatives (swap into applications/)
│   ├── rhoai-platform.yaml
│   ├── rhoai-inference.yaml
│   ├── rhoai-platform-disconnected.yaml
│   ├── rhoai-inference-disconnected.yaml
│   └── 00-servicemesh-disconnected.yaml
├── values/                                  # Standalone values files for helm CLI
│   ├── full-platform.yaml
│   └── inference-only.yaml
├── sealed-secrets/                          # Registry credentials (if using OCI source)
│   └── registry-secret.yaml.template
└── imageset-config-template.yaml           # Mirror config for disconnected
```

---

## Chart Source

Extracted from the official Red Hat OCI registry:

```bash
helm registry login registry.redhat.io
helm pull oci://registry.redhat.io/rhai/rhai-on-openshift-chart --version v3.5 --untar
```

- **Upstream**: [opendatahub-io/odh-gitops](https://github.com/opendatahub-io/odh-gitops)
- **Red Hat Developer article**: [Automating RHOAI installations with Helm and GitOps](https://developers.redhat.com/articles/2026/08/26/automating-red-hat-openshift-ai-installations-with-helm-and-gitops)
