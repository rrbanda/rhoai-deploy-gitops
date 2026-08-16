# AutoRAG on Red Hat OpenShift AI 3.4 — Complete Setup Guide

Deploy AutoRAG (Technology Preview) on RHOAI 3.4 for automated RAG pipeline optimization. This guide works on both connected and disconnected (air-gapped) clusters, with configurable LLM inference (local GPU or external API).

## What AutoRAG Does

AutoRAG finds the best Retrieval-Augmented Generation (RAG) configuration for your documents. You provide documents and test questions; AutoRAG tests combinations of chunking, embedding, retrieval, and generation settings, ranks them on a leaderboard, and generates Jupyter notebooks to run the winning pattern.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                        OpenShift Cluster                              │
│                                                                      │
│  ┌─────────────┐   ┌──────────────────────────────────────────────┐ │
│  │ RHOAI 3.4   │   │  autorag namespace                           │ │
│  │ Operator     │   │                                              │ │
│  │             │   │  ┌────────────┐  ┌─────────────────────────┐│ │
│  │ DataScience │   │  │ Llama Stack│  │ Pipeline Server (DSPA)  ││ │
│  │ Cluster     │   │  │ Distribution│  │ + Workflow Controller   ││ │
│  │ (default-dsc)│   │  └─────┬──────┘  └────────────┬───────────┘│ │
│  └─────────────┘   │        │                       │            │ │
│                     │  ┌─────▼──────┐  ┌────────────▼──────────┐ │ │
│                     │  │ Milvus     │  │ AutoRAG Pipeline       │ │ │
│                     │  │ + etcd     │  │ (Kubeflow)             │ │ │
│                     │  └────────────┘  └────────────────────────┘ │ │
│                     │                                              │ │
│                     │  ┌────────────┐  ┌────────────────────────┐ │ │
│                     │  │ PostgreSQL │  │ MinIO (S3 Storage)     │ │ │
│                     │  │ (metadata) │  │ Documents + Results    │ │ │
│                     │  └────────────┘  └────────────────────────┘ │ │
│                     └──────────────────────────────────────────────┘ │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │ LLM Inference (CONFIGURABLE)                                  │   │
│  │   Option A: vLLM on local GPU node                            │   │
│  │   Option B: External OpenAI-compatible API endpoint           │   │
│  └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

| Requirement | Details |
|---|---|
| OpenShift | 4.16+ with cluster-admin access |
| RHOAI 3.4 | Operator installed (channel: `fast` for GA, `beta` for EA) |
| Storage | Default StorageClass that provisions PVCs |
| GPU (optional) | NVIDIA GPU node with NFD + GPU Operator (only for local LLM) |
| oc CLI | Logged in as cluster-admin |

## Configuration Variables

Edit these values before running the commands. All steps below reference these variables.

```bash
# --- Required ---
export NAMESPACE="autorag"
export MINIO_USER="minio"
export MINIO_PASSWORD="minio123"
export MINIO_BUCKET_DOCS="autorag-documents"
export MINIO_BUCKET_RESULTS="autorag-results"
export POSTGRES_USER="llamastack"
export POSTGRES_PASSWORD="llamastack123"
export POSTGRES_DB="llamastack"
export MILVUS_TOKEN="root:Milvus"

# --- LLM Configuration (choose one) ---
# Option A: Local GPU model (requires NVIDIA GPU node)
export LLM_MODE="local-gpu"
export INFERENCE_MODEL="meta-llama/Llama-3.2-3B-Instruct"

# Option B: External API endpoint (no GPU required)
# export LLM_MODE="external-api"
# export VLLM_URL="https://your-model-endpoint.example.com/v1"
# export INFERENCE_MODEL="your-model-name"
# export VLLM_API_TOKEN="your-api-key"

# --- Disconnected cluster only ---
# export REGISTRY="myregistry.example.com:5000"
# export MILVUS_IMAGE="${REGISTRY}/milvusdb/milvus:v2.5.4"
# export ETCD_IMAGE="${REGISTRY}/coreos/etcd:v3.5.16"
# export MINIO_IMAGE="${REGISTRY}/minio/minio:latest"
# export MC_IMAGE="${REGISTRY}/minio/mc:latest"
# export POSTGRES_IMAGE="${REGISTRY}/rhel9/postgresql-15:latest"
```

---

## Disconnected (Air-Gapped) Cluster: Complete Setup

> Skip this entire section if your cluster has internet access.

A disconnected deployment requires three things:
1. **Mirrored operator catalog** — so OLM can install the RHOAI operator
2. **Mirrored workload images** — containers used by AutoRAG at runtime
3. **ImageDigestMirrorSet (IDMS)** — tells the cluster to pull from your registry instead of the internet

### A. Images to Mirror

#### Operator Catalog Images (via `oc-mirror`)

These are pulled by OLM during operator install/upgrade:

| Package | Source Catalog | Channel |
|---|---|---|
| `rhods-operator` | `registry.redhat.io/redhat/redhat-operator-index:v4.18` | `fast` (GA) or `beta` (EA) |

The `rhods-operator` package bundles the Llama Stack operator, pipeline controller, and all RHOAI components. You do not need to mirror Llama Stack separately as an operator.

#### Workload Images (via `skopeo` or `oc-mirror additionalImages`)

These are pulled at **runtime** by pods — they are NOT in the operator catalog:

| Image | Purpose | Required? |
|---|---|---|
| `docker.io/milvusdb/milvus:v2.5.4` | Vector database | Yes |
| `quay.io/coreos/etcd:v3.5.16` | Milvus metadata coordination | Yes |
| `registry.redhat.io/rhel9/postgresql-15:latest` | Llama Stack metadata store | Yes |
| `registry.redhat.io/rhoai/odh-llama-stack-core-rhel9:*` | Llama Stack server (pulled by operator) | Yes |
| `quay.io/minio/minio:latest` | S3 object storage | Only if deploying MinIO |
| `quay.io/minio/mc:latest` | MinIO client (bucket creation) | Only if deploying MinIO |
| `registry.redhat.io/rhaiis/vllm-cuda-rhel9:3.3.0` | vLLM model serving runtime | Only for local GPU (Option A) |

#### Pipeline Task Images

The AutoRAG Kubeflow pipeline uses task containers. These are referenced inside the pipeline YAML and are pulled when the pipeline runs:

| Image | Purpose |
|---|---|
| `registry.redhat.io/rhoai/odh-autorag-eval-rhel9:*` | AutoRAG evaluation task |
| `registry.redhat.io/rhoai/odh-autorag-data-ingestion-rhel9:*` | Document ingestion task |
| `registry.redhat.io/rhoai/odh-ds-pipelines-launcher-rhel9:*` | Kubeflow launcher |
| `registry.redhat.io/rhoai/odh-ds-pipelines-driver-rhel9:*` | Kubeflow driver |

> **Tip:** To get the exact image digests for your RHOAI version, check the [RHOAI Disconnected Install Helper](https://github.com/red-hat-data-services/rhoai-disconnected-install-helper). It lists every image for each RHOAI release.

### B. Mirror the Images

#### Option 1: `oc-mirror` (recommended for operators + images together)

Create an `ImageSetConfiguration`:

```yaml
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1
mirror:
  operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.18
      packages:
        - name: rhods-operator
          channels:
            - name: fast
              minVersion: "3.4.0"
              maxVersion: "3.4.0"

  additionalImages:
    # AutoRAG infrastructure
    - name: docker.io/milvusdb/milvus:v2.5.4
    - name: quay.io/coreos/etcd:v3.5.16
    - name: registry.redhat.io/rhel9/postgresql-15:latest
    - name: quay.io/minio/minio:latest
    - name: quay.io/minio/mc:latest

    # Llama Stack (check exact tag for your RHOAI version)
    - name: registry.redhat.io/rhoai/odh-llama-stack-core-rhel9:latest

    # Pipeline tasks (check exact digests from rhoai-disconnected-install-helper)
    - name: registry.redhat.io/rhoai/odh-autorag-eval-rhel9:latest
    - name: registry.redhat.io/rhoai/odh-autorag-data-ingestion-rhel9:latest
    - name: registry.redhat.io/rhoai/odh-ds-pipelines-launcher-rhel9:latest
    - name: registry.redhat.io/rhoai/odh-ds-pipelines-driver-rhel9:latest

    # vLLM (only if using local GPU - Option A)
    - name: registry.redhat.io/rhaiis/vllm-cuda-rhel9:3.3.0
```

Run the mirror:

```bash
oc mirror --config=imageset-config-autorag.yaml \
  docker://${REGISTRY}
```

This generates IDMS and CatalogSource YAMLs in the `oc-mirror-workspace/` results directory.

#### Option 2: Manual `skopeo` (for individual images)

```bash
# Infrastructure images
IMAGES=(
  "docker.io/milvusdb/milvus:v2.5.4"
  "quay.io/coreos/etcd:v3.5.16"
  "quay.io/minio/minio:latest"
  "quay.io/minio/mc:latest"
  "registry.redhat.io/rhel9/postgresql-15:latest"
  "registry.redhat.io/rhoai/odh-llama-stack-core-rhel9:latest"
  "registry.redhat.io/rhoai/odh-autorag-eval-rhel9:latest"
  "registry.redhat.io/rhoai/odh-autorag-data-ingestion-rhel9:latest"
  "registry.redhat.io/rhoai/odh-ds-pipelines-launcher-rhel9:latest"
  "registry.redhat.io/rhoai/odh-ds-pipelines-driver-rhel9:latest"
)

for img in "${IMAGES[@]}"; do
  # Strip the registry prefix for the destination path
  dest_path="${img#*/}"
  skopeo copy --all \
    docker://${img} \
    docker://${REGISTRY}/${dest_path}
done

# If using local GPU model serving:
skopeo copy --all \
  docker://registry.redhat.io/rhaiis/vllm-cuda-rhel9:3.3.0 \
  docker://${REGISTRY}/rhaiis/vllm-cuda-rhel9:3.3.0
```

### C. Create the CatalogSource

After mirroring, create a CatalogSource pointing to your mirrored operator index:

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: cs-redhat-operator-index
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: ${REGISTRY}/redhat/redhat-operator-index:v4.18
  displayName: Red Hat Operators (Mirrored)
  publisher: Red Hat (mirrored)
  updateStrategy:
    registryPoll:
      interval: 30m
```

```bash
# Apply the CatalogSource
oc apply -f catalogsource.yaml

# Verify it's ready
oc get catalogsource cs-redhat-operator-index -n openshift-marketplace \
  -o jsonpath='{.status.connectionState.lastObservedState}'
# Expected: READY
```

### D. Create the ImageDigestMirrorSet (IDMS)

This tells the cluster to redirect image pulls from public registries to your mirror:

```yaml
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
metadata:
  name: autorag-mirrors
spec:
  imageDigestMirrorSet:
  - mirrors:
    - ${REGISTRY}/milvusdb
    source: docker.io/milvusdb
  - mirrors:
    - ${REGISTRY}/coreos
    source: quay.io/coreos
  - mirrors:
    - ${REGISTRY}/minio
    source: quay.io/minio
  - mirrors:
    - ${REGISTRY}/rhel9
    source: registry.redhat.io/rhel9
  - mirrors:
    - ${REGISTRY}/rhoai
    source: registry.redhat.io/rhoai
  - mirrors:
    - ${REGISTRY}/rhaiis
    source: registry.redhat.io/rhaiis
```

```bash
oc apply -f idms-autorag.yaml

# Nodes will gradually restart MachineConfigPools to pick up mirror config
oc get mcp
```

> **Note:** If `oc-mirror` was used, it automatically generates the IDMS YAML — apply it from `oc-mirror-workspace/results-*/` instead of creating manually.

### E. Disconnected Operator Subscription

When installing RHOAI on a disconnected cluster, point the Subscription to your mirrored CatalogSource:

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  channel: fast
  installPlanApproval: Automatic
  name: rhods-operator
  source: cs-redhat-operator-index          # <-- Your mirrored CatalogSource
  sourceNamespace: openshift-marketplace
```

### F. Verify Mirroring is Complete

```bash
# Check that RHOAI operator can be resolved from the mirrored catalog
oc get packagemanifest rhods-operator -o jsonpath='{.status.catalogSource}'
# Expected: cs-redhat-operator-index

# Check IDMS is applied
oc get imagedigestmirrorset autorag-mirrors

# Test pulling an image through the mirror
oc debug node/$(oc get nodes -o jsonpath='{.items[0].metadata.name}') -- \
  chroot /host crictl pull ${REGISTRY}/milvusdb/milvus:v2.5.4
```

---

## Step 1: Verify RHOAI 3.4 is Installed

```bash
oc get csv -n redhat-ods-operator | grep rhods
```

Expected output should show `rhods-operator.3.4.x` with status `Succeeded`.

If not installed, apply the operator subscription:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: redhat-ods-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: redhat-ods-operator
  namespace: redhat-ods-operator
spec: {}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  channel: fast          # Use 'fast' for RHOAI 3.4 GA
  installPlanApproval: Automatic
  name: rhods-operator
  source: redhat-operators          # Change for disconnected (see below)
  sourceNamespace: openshift-marketplace
```

**Disconnected:** Replace `source: redhat-operators` with your mirrored CatalogSource name (e.g., `cs-redhat-operator-index`).

Verify the DataScienceCluster exists:

```bash
oc get datasciencecluster
```

---

## Step 2: Enable the Llama Stack Operator

The Llama Stack Operator must be set to `Managed` in the DataScienceCluster:

```bash
oc patch datasciencecluster default-dsc --type=merge \
  -p '{"spec":{"components":{"llamastackoperator":{"managementState":"Managed"}}}}'
```

Verify the operator pod is running:

```bash
oc get pods -n redhat-ods-applications -l name=llama-stack-k8s-operator
```

Expected: pod in `Running` state.

---

## Step 3: Create the AutoRAG Project Namespace

```bash
oc new-project ${NAMESPACE} || oc project ${NAMESPACE}

# Label as a Data Science project (required for RHOAI dashboard visibility)
oc label namespace ${NAMESPACE} opendatahub.io/dashboard=true --overwrite
oc label namespace ${NAMESPACE} modelmesh-enabled=true --overwrite
```

---

## Step 4: Deploy MinIO (S3 Storage)

> Skip this step if you already have S3-compatible storage (AWS S3, Noobaa, etc.). Update the connection variables accordingly.

```bash
cat <<EOF | oc apply -n ${NAMESPACE} -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: minio-secret
type: Opaque
stringData:
  MINIO_ROOT_USER: "${MINIO_USER}"
  MINIO_ROOT_PASSWORD: "${MINIO_PASSWORD}"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-data
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  labels:
    app: minio
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: quay.io/minio/minio:latest    # Disconnected: use \${MINIO_IMAGE}
        args: ["server", "/data", "--console-address", ":9090"]
        env:
        - name: MINIO_ROOT_USER
          valueFrom:
            secretKeyRef:
              name: minio-secret
              key: MINIO_ROOT_USER
        - name: MINIO_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: minio-secret
              key: MINIO_ROOT_PASSWORD
        ports:
        - containerPort: 9000
          name: api
        - containerPort: 9090
          name: console
        volumeMounts:
        - name: data
          mountPath: /data
        resources:
          requests: {cpu: "100m", memory: "256Mi"}
          limits: {cpu: "1", memory: "1Gi"}
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: minio-data
---
apiVersion: v1
kind: Service
metadata:
  name: minio-service
  labels:
    app: minio
spec:
  ports:
  - port: 9000
    name: api
  - port: 9090
    name: console
  selector:
    app: minio
EOF
```

Wait for MinIO to be ready, then create buckets:

```bash
oc wait --for=condition=available deployment/minio -n ${NAMESPACE} --timeout=120s

cat <<EOF | oc apply -n ${NAMESPACE} -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: create-buckets
spec:
  template:
    spec:
      containers:
      - name: mc
        image: quay.io/minio/mc:latest       # Disconnected: use \${MC_IMAGE}
        env:
        - name: HOME
          value: /tmp
        command: ["/bin/sh", "-c"]
        args:
        - |
          mc alias set myminio http://minio-service:9000 ${MINIO_USER} ${MINIO_PASSWORD}
          mc mb myminio/${MINIO_BUCKET_DOCS} --ignore-existing
          mc mb myminio/${MINIO_BUCKET_RESULTS} --ignore-existing
          mc ls myminio/
      restartPolicy: Never
  backoffLimit: 3
EOF

# Wait for completion
oc wait --for=condition=complete job/create-buckets -n ${NAMESPACE} --timeout=120s
oc delete job create-buckets -n ${NAMESPACE}
```

---

## Step 5: Deploy etcd + Milvus (Vector Database)

AutoRAG requires a **remote** Milvus instance (inline Milvus is not supported).

### 5a. Deploy etcd

```bash
cat <<EOF | oc apply -n ${NAMESPACE} -f -
---
apiVersion: v1
kind: Service
metadata:
  name: etcd
spec:
  ports:
  - port: 2379
    name: client
  - port: 2380
    name: peer
  selector:
    app: etcd
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: etcd
spec:
  serviceName: etcd
  replicas: 1
  selector:
    matchLabels:
      app: etcd
  template:
    metadata:
      labels:
        app: etcd
    spec:
      containers:
      - name: etcd
        image: quay.io/coreos/etcd:v3.5.16   # Disconnected: use \${ETCD_IMAGE}
        command:
        - etcd
        - --advertise-client-urls=http://etcd:2379
        - --listen-client-urls=http://0.0.0.0:2379
        - --listen-peer-urls=http://0.0.0.0:2380
        - --initial-advertise-peer-urls=http://etcd:2380
        - --initial-cluster=default=http://etcd:2380
        - --data-dir=/etcd-data
        ports:
        - containerPort: 2379
        - containerPort: 2380
        volumeMounts:
        - name: etcd-data
          mountPath: /etcd-data
        resources:
          requests: {cpu: "100m", memory: "256Mi"}
          limits: {cpu: "500m", memory: "512Mi"}
  volumeClaimTemplates:
  - metadata:
      name: etcd-data
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 5Gi
EOF
```

### 5b. Deploy Milvus

> **Important:** Use Milvus v2.5.4+. Earlier versions (v2.4.x) have a startup race condition that causes panics in standalone mode.

```bash
cat <<EOF | oc apply -n ${NAMESPACE} -f -
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: milvus-data
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 20Gi
---
apiVersion: v1
kind: Service
metadata:
  name: milvus-service
  labels:
    app: milvus
spec:
  ports:
  - port: 19530
    name: grpc
  - port: 9091
    name: metrics
  selector:
    app: milvus
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: milvus
  labels:
    app: milvus
spec:
  strategy:
    type: Recreate            # Avoids PVC multi-attach conflicts
  replicas: 1
  selector:
    matchLabels:
      app: milvus
  template:
    metadata:
      labels:
        app: milvus
    spec:
      containers:
      - name: milvus
        image: milvusdb/milvus:v2.5.4        # Disconnected: use \${MILVUS_IMAGE}
        command: [milvus, run, standalone]
        env:
        - name: ETCD_ENDPOINTS
          value: "etcd:2379"
        - name: MINIO_ADDRESS
          value: "minio-service:9000"
        - name: MINIO_ACCESS_KEY_ID
          value: "${MINIO_USER}"
        - name: MINIO_SECRET_ACCESS_KEY
          value: "${MINIO_PASSWORD}"
        - name: MINIO_USE_SSL
          value: "false"
        - name: MINIO_BUCKET_NAME
          value: "${MINIO_BUCKET_RESULTS}"
        - name: MINIO_ROOT_PATH
          value: "milvus"
        ports:
        - containerPort: 19530
        - containerPort: 9091
        volumeMounts:
        - name: milvus-data
          mountPath: /var/lib/milvus
        resources:
          requests: {cpu: "500m", memory: "2Gi"}
          limits: {cpu: "2", memory: "4Gi"}
      volumes:
      - name: milvus-data
        persistentVolumeClaim:
          claimName: milvus-data
EOF
```

Wait for both to be ready:

```bash
oc wait --for=condition=ready pod -l app=etcd -n ${NAMESPACE} --timeout=180s
oc wait --for=condition=available deployment/milvus -n ${NAMESPACE} --timeout=300s
```

### 5c. Create Milvus secret for Llama Stack

```bash
cat <<EOF | oc apply -n ${NAMESPACE} -f -
apiVersion: v1
kind: Secret
metadata:
  name: milvus-secret
type: Opaque
stringData:
  MILVUS_ENDPOINT: "tcp://milvus-service:19530"
  MILVUS_TOKEN: "${MILVUS_TOKEN}"
  MILVUS_CONSISTENCY_LEVEL: "Bounded"
EOF
```

---

## Step 6: Deploy PostgreSQL (Llama Stack Metadata Store)

```bash
cat <<EOF | oc apply -n ${NAMESPACE} -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
type: Opaque
stringData:
  password: "${POSTGRES_PASSWORD}"
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  ports:
  - port: 5432
  selector:
    app: postgres
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: registry.redhat.io/rhel9/postgresql-15:latest  # Disconnected: use \${POSTGRES_IMAGE}
        env:
        - name: POSTGRESQL_USER
          value: "${POSTGRES_USER}"
        - name: POSTGRESQL_PASSWORD
          value: "${POSTGRES_PASSWORD}"
        - name: POSTGRESQL_DATABASE
          value: "${POSTGRES_DB}"
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: data
          mountPath: /var/lib/pgsql/data
        resources:
          requests: {cpu: "100m", memory: "256Mi"}
          limits: {cpu: "500m", memory: "512Mi"}
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: postgres-data
EOF

oc wait --for=condition=available deployment/postgres -n ${NAMESPACE} --timeout=120s
```

---

## Step 7: Configure LLM Inference

### Option A: Local GPU (vLLM on cluster)

> Requires: NVIDIA GPU node with NFD + GPU Operator installed.

Deploy a model using the RHOAI single-model serving platform. This example deploys Llama 3.2 3B:

```bash
# Create a ServingRuntime + InferenceService via the RHOAI dashboard,
# or apply directly:
cat <<EOF | oc apply -n ${NAMESPACE} -f -
apiVersion: serving.kserve.io/v1alpha1
kind: ServingRuntime
metadata:
  name: vllm-runtime
spec:
  annotations:
    openshift.io/display-name: vLLM
  supportedModelFormats:
  - autoSelect: true
    name: vLLM
  containers:
  - name: kserve-container
    image: registry.redhat.io/rhaiis/vllm-cuda-rhel9:3.3.0
    args:
    - --model=/mnt/models
    - --port=8080
    ports:
    - containerPort: 8080
      protocol: TCP
    resources:
      limits:
        nvidia.com/gpu: "1"
        cpu: "4"
        memory: "24Gi"
      requests:
        nvidia.com/gpu: "1"
        cpu: "2"
        memory: "16Gi"
---
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: llm-model
spec:
  predictor:
    model:
      modelFormat:
        name: vLLM
      runtime: vllm-runtime
      storageUri: "hf://${INFERENCE_MODEL}"
      resources:
        limits:
          nvidia.com/gpu: "1"
    tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
EOF

# Wait for model to be ready (this may take 5-10 minutes for model download)
oc wait --for=condition=ready inferenceservice/llm-model -n ${NAMESPACE} --timeout=600s

# Get the endpoint URL
export VLLM_URL="http://llm-model-predictor.${NAMESPACE}.svc.cluster.local/v1"
export VLLM_API_TOKEN=""
```

### Option B: External API Endpoint (No GPU Required)

Point to any OpenAI-compatible endpoint. No local model deployment needed.

Llama Stack's `remote::vllm` provider works with **any** endpoint that implements the OpenAI `/v1/chat/completions` API — the name is misleading, it's not limited to vLLM:

```bash
# Set these from your external provider:
export VLLM_URL="https://your-model-api.example.com/v1"
export INFERENCE_MODEL="your-model-id"
export VLLM_API_TOKEN="your-api-key"
```

**Examples with popular providers:**

```bash
# Together AI
export VLLM_URL="https://api.together.xyz/v1"
export INFERENCE_MODEL="meta-llama/Llama-3.2-3B-Instruct"
export VLLM_API_TOKEN="your-together-key"

# Groq
export VLLM_URL="https://api.groq.com/openai/v1"
export INFERENCE_MODEL="llama-3.3-70b-versatile"
export VLLM_API_TOKEN="gsk_your-groq-key"

# OpenAI
export VLLM_URL="https://api.openai.com/v1"
export INFERENCE_MODEL="gpt-4o"
export VLLM_API_TOKEN="sk-your-openai-key"

# Azure OpenAI
export VLLM_URL="https://your-resource.openai.azure.com/openai/deployments/your-deployment/v1"
export INFERENCE_MODEL="your-deployment-name"
export VLLM_API_TOKEN="your-azure-key"

# Ollama (running elsewhere, no auth)
export VLLM_URL="http://ollama-host:11434/v1"
export INFERENCE_MODEL="llama3.2"
export VLLM_API_TOKEN=""

# Another OpenShift cluster running vLLM
export VLLM_URL="https://my-model-predictor.apps.other-cluster.example.com/v1"
export INFERENCE_MODEL="Qwen/Qwen3-4B"
export VLLM_API_TOKEN=""
```

> **Note:** Llama Stack also supports dedicated providers (`remote::openai`, `remote::azure`, `remote::bedrock`, `remote::watsonx`, `remote::vertexai`) but `remote::vllm` with the correct URL works for all OpenAI-compatible endpoints and is the simplest approach.

### Create the Llama Stack model secret

```bash
cat <<EOF | oc apply -n ${NAMESPACE} -f -
apiVersion: v1
kind: Secret
metadata:
  name: llama-stack-secret
type: Opaque
stringData:
  VLLM_URL: "${VLLM_URL}"
  INFERENCE_MODEL: "${INFERENCE_MODEL}"
  VLLM_TLS_VERIFY: "false"
  VLLM_API_TOKEN: "${VLLM_API_TOKEN:-}"
EOF
```

---

## Step 8: Deploy LlamaStackDistribution

This creates the Llama Stack server that AutoRAG uses for embedding, retrieval, and generation:

```bash
cat <<EOF | oc apply -n ${NAMESPACE} -f -
apiVersion: llamastack.io/v1alpha1
kind: LlamaStackDistribution
metadata:
  name: autorag-llamastack
spec:
  replicas: 1
  server:
    containerSpec:
      resources:
        requests: {cpu: "250m", memory: "1Gi"}
        limits: {cpu: "2", memory: "4Gi"}
      env:
      - name: POSTGRES_HOST
        value: postgres
      - name: POSTGRES_PORT
        value: "5432"
      - name: POSTGRES_DB
        value: "${POSTGRES_DB}"
      - name: POSTGRES_USER
        value: "${POSTGRES_USER}"
      - name: POSTGRES_PASSWORD
        valueFrom:
          secretKeyRef:
            name: postgres-secret
            key: password
      - name: ENABLE_SENTENCE_TRANSFORMERS
        value: "true"
      - name: EMBEDDING_PROVIDER
        value: "sentence-transformers"
      - name: INFERENCE_MODEL
        valueFrom:
          secretKeyRef:
            name: llama-stack-secret
            key: INFERENCE_MODEL
      - name: VLLM_MAX_TOKENS
        value: "4096"
      - name: VLLM_URL
        valueFrom:
          secretKeyRef:
            name: llama-stack-secret
            key: VLLM_URL
      - name: VLLM_TLS_VERIFY
        valueFrom:
          secretKeyRef:
            name: llama-stack-secret
            key: VLLM_TLS_VERIFY
      - name: VLLM_API_TOKEN
        valueFrom:
          secretKeyRef:
            name: llama-stack-secret
            key: VLLM_API_TOKEN
      - name: MILVUS_ENDPOINT
        valueFrom:
          secretKeyRef:
            name: milvus-secret
            key: MILVUS_ENDPOINT
      - name: MILVUS_TOKEN
        valueFrom:
          secretKeyRef:
            name: milvus-secret
            key: MILVUS_TOKEN
      - name: MILVUS_CONSISTENCY_LEVEL
        valueFrom:
          secretKeyRef:
            name: milvus-secret
            key: MILVUS_CONSISTENCY_LEVEL
      name: llama-stack
      port: 8321
    distribution:
      name: rh-dev
    storage:
      size: 10Gi
EOF
```

Wait for the LlamaStackDistribution to become Ready:

```bash
# This may take 2-3 minutes (downloads sentence-transformers model on first start)
oc wait --for=jsonpath='{.status.phase}'=Ready \
  llamastackdistribution/autorag-llamastack -n ${NAMESPACE} --timeout=300s

# Verify the service URL
oc get llamastackdistribution autorag-llamastack -n ${NAMESPACE} \
  -o jsonpath='{.status.serviceURL}'
```

> **Troubleshooting:** If the pod keeps restarting, ensure Milvus is healthy first (`oc get pods -l app=milvus`). The Llama Stack startup probe will kill the pod if Milvus gRPC port 19530 is not responding.

---

## Step 9: Create the Pipeline Server

The Data Science Pipelines Application (DSPA) runs the AutoRAG optimization pipeline:

```bash
cat <<EOF | oc apply -n ${NAMESPACE} -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: aws-connection-pipeline-artifacts
  labels:
    opendatahub.io/dashboard: "true"
    opendatahub.io/managed: "true"
  annotations:
    opendatahub.io/connection-type: s3
    openshift.io/display-name: Pipeline Artifacts S3
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "${MINIO_USER}"
  AWS_SECRET_ACCESS_KEY: "${MINIO_PASSWORD}"
  AWS_S3_ENDPOINT: "http://minio-service.${NAMESPACE}.svc.cluster.local:9000"
  AWS_S3_BUCKET: "${MINIO_BUCKET_RESULTS}"
  AWS_DEFAULT_REGION: "us-east-1"
---
apiVersion: datasciencepipelinesapplications.opendatahub.io/v1
kind: DataSciencePipelinesApplication
metadata:
  name: dspa
spec:
  dspVersion: v2
  apiServer:
    enableSamplePipeline: false
  objectStorage:
    externalStorage:
      host: "minio-service.${NAMESPACE}.svc.cluster.local"
      port: "9000"
      bucket: "${MINIO_BUCKET_RESULTS}"
      scheme: http
      region: us-east-1
      s3CredentialsSecret:
        accessKey: AWS_ACCESS_KEY_ID
        secretKey: AWS_SECRET_ACCESS_KEY
        secretName: aws-connection-pipeline-artifacts
EOF
```

Wait for the pipeline server:

```bash
oc wait --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True \
  dspa/dspa -n ${NAMESPACE} --timeout=300s
```

> **Troubleshooting:** If the DSPA reports "Could not connect to MinIO", check the Network Policy section below.

---

## Step 10: Network Policies (Critical)

If your MinIO is in a **different namespace** than AutoRAG (or if network policies restrict cross-namespace traffic), you must allow:

1. The `autorag` namespace pods to reach MinIO
2. The `redhat-ods-applications` namespace (where the DSPA controller runs) to reach MinIO

```bash
# Replace 'minio' with the namespace where MinIO runs
MINIO_NAMESPACE="minio"  # Change if MinIO is in the same namespace as autorag

cat <<EOF | oc apply -n ${MINIO_NAMESPACE} -f -
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-autorag-to-minio
spec:
  podSelector:
    matchLabels:
      app: minio
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ${NAMESPACE}
    ports:
    - port: 9000
      protocol: TCP
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-rhoai-controller-to-minio
spec:
  podSelector:
    matchLabels:
      app: minio
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: redhat-ods-applications
    ports:
    - port: 9000
      protocol: TCP
  policyTypes: [Ingress]
EOF
```

> If MinIO is deployed in the **same namespace** as AutoRAG (as shown in Step 4), you can skip this step — same-namespace traffic is allowed by default unless you have explicit deny-all policies.

---

## Step 11: Create Data Connections

```bash
cat <<EOF | oc apply -n ${NAMESPACE} -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: aws-connection-minio
  labels:
    opendatahub.io/dashboard: "true"
    opendatahub.io/managed: "true"
  annotations:
    opendatahub.io/connection-type: s3
    openshift.io/display-name: "AutoRAG Documents S3"
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "${MINIO_USER}"
  AWS_SECRET_ACCESS_KEY: "${MINIO_PASSWORD}"
  AWS_S3_ENDPOINT: "http://minio-service.${NAMESPACE}.svc.cluster.local:9000"
  AWS_S3_BUCKET: "${MINIO_BUCKET_DOCS}"
  AWS_DEFAULT_REGION: "us-east-1"
---
apiVersion: v1
kind: Secret
metadata:
  name: llamastack-connection
  labels:
    opendatahub.io/dashboard: "true"
    opendatahub.io/managed: "true"
  annotations:
    opendatahub.io/connection-type: llamastack
    openshift.io/display-name: "AutoRAG Llama Stack"
type: Opaque
stringData:
  LLAMA_STACK_CLIENT_BASE_URL: "http://autorag-llamastack-service.${NAMESPACE}.svc.cluster.local:8321"
  LLAMA_STACK_CLIENT_API_KEY: ""
EOF
```

---

## Step 12: Import the Fixed AutoRAG Pipeline

> **Known Issue (RHOAIENG-64768):** The default pipeline shipped with RHOAI 3.4 references container images that may not be available. Download the fixed version.

```bash
# Download the fixed pipeline definition
curl -sL -o /tmp/autorag-pipeline.yaml \
  "https://raw.githubusercontent.com/red-hat-data-services/pipelines-components/rhoai-3.4-fixed/pipelines/training/autorag/documents_rag_optimization_pipeline/pipeline.yaml"

# Get auth token
TOKEN=$(oc whoami -t)

# Get the pipeline server route
DSPA_ROUTE=$(oc get route ds-pipeline-dspa -n ${NAMESPACE} -o jsonpath='{.spec.host}')

# Upload the pipeline
curl -sk -X POST \
  "https://${DSPA_ROUTE}/apis/v2beta1/pipelines/upload?name=documents-rag-optimization-pipeline&description=AutoRAG+fixed+pipeline" \
  -H "Authorization: Bearer ${TOKEN}" \
  -F "uploadfile=@/tmp/autorag-pipeline.yaml"
```

**Disconnected:** Download the pipeline YAML on a connected machine first and transfer it to your bastion. The pipeline YAML itself does not need modification — the image references inside it are resolved by the pipeline runtime using your cluster's IDMS/ICSP mirror rules.

---

## Step 13: Upload Documents and Test Data

Upload your documents and evaluation data to the S3 bucket:

```bash
# Example: upload a sample document and benchmark
cat <<'ENDDOC' > /tmp/my-document.txt
Your document content here...
ENDDOC

cat <<'ENDJSON' > /tmp/benchmark_data.json
[
  {
    "question": "What is the main topic of the document?",
    "correct_answers": ["The document is about..."],
    "correct_answer_document_ids": ["my-document.txt"]
  }
]
ENDJSON

# Upload via a Job (works from within the cluster)
cat <<EOF | oc apply -n ${NAMESPACE} -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: upload-docs
spec:
  template:
    spec:
      containers:
      - name: mc
        image: quay.io/minio/mc:latest
        env:
        - name: HOME
          value: /tmp
        command: ["/bin/sh", "-c"]
        args:
        - |
          mc alias set s3 http://minio-service:9000 ${MINIO_USER} ${MINIO_PASSWORD}
          # Upload your documents here:
          echo "Upload your docs via mc cp or the MinIO console"
          mc ls s3/${MINIO_BUCKET_DOCS}/
      restartPolicy: Never
  backoffLimit: 1
EOF
```

Alternatively, use the MinIO console (create a Route) or the RHOAI dashboard to upload files directly when creating the AutoRAG run.

---

## Step 14: Run AutoRAG

### Via the RHOAI Dashboard (Recommended)

1. Open the RHOAI Dashboard
2. Navigate to **Gen AI studio > AutoRAG**
3. Select the `autorag` project
4. Click **Create AutoRAG optimization run**
5. Select the **AutoRAG Llama Stack** connection
6. Configure:
   - **Documents:** Browse/upload from S3 or upload directly
   - **Vector DB:** Select the Milvus provider
   - **Evaluation data:** Upload your `benchmark_data.json`
   - **Optimization metric:** Answer faithfulness (default), Answer correctness, or Context correctness
   - **Max RAG patterns:** 4-20 (default: 8)
7. Click **Create run**

### Via the Pipeline API (Programmatic)

```bash
TOKEN=$(oc whoami -t)
DSPA_ROUTE=$(oc get route ds-pipeline-dspa -n ${NAMESPACE} -o jsonpath='{.spec.host}')

# List pipelines to get the pipeline_id
curl -sk "https://${DSPA_ROUTE}/apis/v2beta1/pipelines" \
  -H "Authorization: Bearer ${TOKEN}" | python3 -m json.tool
```

---

## Verification Checklist

```bash
echo "=== Pods ==="
oc get pods -n ${NAMESPACE}

echo "=== LlamaStackDistribution ==="
oc get llamastackdistribution -n ${NAMESPACE}

echo "=== Pipeline Server ==="
oc get dspa -n ${NAMESPACE}

echo "=== Connections ==="
oc get secrets -n ${NAMESPACE} -l opendatahub.io/dashboard=true \
  -o custom-columns=NAME:.metadata.name,TYPE:.metadata.annotations.opendatahub\\.io/connection-type
```

All pods should be `Running`, LSD phase should be `Ready`, DSPA should exist.

---

## Known Issues and Solutions

| Issue | Symptom | Fix |
|---|---|---|
| Pipeline image pull errors (RHOAIENG-64768) | Pipeline tasks stuck in `ImagePullBackOff` | Use the fixed pipeline YAML from `rhoai-3.4-fixed` branch (Step 12) |
| Milvus startup panic | `CrashLoopBackOff` with gRPC stack trace | Use Milvus v2.5.4+ (not v2.4.x). Set deployment strategy to `Recreate` |
| Milvus MinIO auth failure | "Access Key Id does not exist" in Milvus logs | Use `MINIO_ACCESS_KEY_ID` (not `MINIO_ACCESS_KEY`) for Milvus v2.5+ |
| DSPA can't connect to MinIO | "context deadline exceeded" in DSPA status | Add NetworkPolicy allowing `redhat-ods-applications` namespace (Step 10) |
| Llama Stack startup probe failure | Pod killed before ready | Ensure Milvus is fully healthy before LSD starts. Restart the LSD pod if needed |
| Missing `MILVUS_CONSISTENCY_LEVEL` | Pydantic validation error in Llama Stack logs | Include `MILVUS_CONSISTENCY_LEVEL: "Bounded"` in the milvus-secret |
| DSPA API version mismatch | "no matches for kind" error | Use `datasciencepipelinesapplications.opendatahub.io/v1` (not v1alpha1) |

---

## Cleanup

To remove the entire AutoRAG deployment:

```bash
oc delete llamastackdistribution autorag-llamastack -n ${NAMESPACE}
oc delete dspa dspa -n ${NAMESPACE}
oc delete deployment milvus postgres minio -n ${NAMESPACE}
oc delete statefulset etcd -n ${NAMESPACE}
oc delete pvc --all -n ${NAMESPACE}
oc delete project ${NAMESPACE}
```

---

## References

- [AutoRAG Overview (RHOAI 3.4 Docs)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_autorag/autorag-overview_autorag)
- [Working with Llama Stack (RHOAI 3.4 Docs)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/working_with_llama_stack/working_with_llama_stack)
- [AutoRAG Examples (GitHub)](https://github.com/red-hat-data-services/red-hat-ai-examples/blob/main/examples/autorag/readme.md)
- [Fixed Pipeline YAML (rhoai-3.4-fixed branch)](https://github.com/red-hat-data-services/pipelines-components/tree/rhoai-3.4-fixed/pipelines/training/autorag/documents_rag_optimization_pipeline)
- [RHOAI Disconnected Install Helper](https://github.com/red-hat-data-services/rhoai-disconnected-install-helper)
