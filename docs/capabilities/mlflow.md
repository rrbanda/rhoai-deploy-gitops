# MLflow

MLflow provides experiment tracking, model registry, dataset management, and tracing for ML workflows. RHOAI deploys a single shared MLflow instance that provides namespace-based isolation through the workspaces feature -- each data science project (Kubernetes namespace) maps to its own MLflow workspace.

!!! info "Support level"

    | RHOAI version | MLflow version | Support level |
    |---------------|----------------|---------------|
    | 3.2 / 3.3 | 3.6.0 | Developer Preview |
    | 3.4 EA1 | 3.10.0 (prerelease) | Developer Preview |
    | 3.4 EA2 | 3.10.1 | Technical Preview |

    For questions, contact Matt Prahl or Humair Khan in `#wg-openshift-ai-mlflow-integration`.

## Dependencies

| Requirement | Type | Path |
|-------------|------|------|
| RHOAI Operator | Operator | `components/operators/rhoai-operator/` |
| DSC `mlflowoperator: Managed` | DSC component | `components/instances/rhoai-instance/` |
| MLflow CR | Instance | `components/instances/mlflow-instance/` |
| Default StorageClass with dynamic provisioning | Cluster | Pre-configured |

## Enable It

MLflow is enabled in the `dev` and `full` overlays.

=== "DSC Patch"

    ```yaml
    spec:
      components:
        mlflowoperator:
          managementState: Managed
    ```

=== "kubectl Patch"

    ```bash
    kubectl patch datasciencecluster default-dsc \
      --type=merge \
      -p '{"spec":{"components":{"mlflowoperator":{"managementState":"Managed"}}}}'
    ```

## Deploy

=== "GitOps"

    The MLflow operator is enabled automatically when the `rhoai-instance` ArgoCD Application points to the `dev` or `full` overlay. The `mlflow-instance` component under `components/instances/mlflow-instance/` is auto-discovered by the `cluster-instances` ApplicationSet and creates the MLflow tracking server in `redhat-ods-applications`.

=== "Manual"

    ```bash
    # 1. Install the RHOAI operator
    oc apply -k components/operators/rhoai-operator/
    oc get csv -A | grep rhods

    # 2. Create DSC with MLflow operator enabled
    oc apply -k components/instances/rhoai-instance/overlays/dev/

    # 3. Wait for DSC
    oc wait --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True \
      datasciencecluster/default-dsc --timeout=600s

    # 4. Create the MLflow instance
    oc apply -k components/instances/mlflow-instance/
    ```

## Verify

```bash
# MLflow operator pods
oc get pods -n redhat-ods-applications -l app.kubernetes.io/name=mlflow-operator

# MLflow tracking server
oc get mlflow -n redhat-ods-applications

# MLflow pods
oc get pods -n redhat-ods-applications -l app.kubernetes.io/name=mlflow
```

## MLflow UI

After deployment the MLflow UI appears in the **Applications** drop-down in the OpenShift console and in the RHOAI / ODH dashboard navigation bar.

## SDK Configuration

### Install the SDK

=== "RHOAI 3.2 / 3.3 (Red Hat fork)"

    ```bash
    pip install "git+https://github.com/red-hat-data-services/mlflow@rhoai-3.3"
    ```

=== "RHOAI 3.4 EA1 (Red Hat fork)"

    ```bash
    pip install "git+https://github.com/red-hat-data-services/mlflow@rhoai-3.4-ea.1"
    ```

=== "RHOAI 3.4 EA1/EA2 (upstream SDK 3.10+)"

    ```bash
    pip install "mlflow>=3.10"
    ```

=== "RHOAI 3.4 GA / MLflow SDK 3.11+"

    ```bash
    pip install "mlflow>=3.11"
    ```

### Set the Tracking URI

```bash
export MLFLOW_TRACKING_URI="https://<dashboard-url>/mlflow"

# If the cluster does not use trusted TLS certificates:
export MLFLOW_TRACKING_INSECURE_TLS=true
```

### Authentication

=== "Manual Token (RHOAI 3.2/3.3 or upstream SDK 3.10+)"

    ```bash
    export MLFLOW_TRACKING_TOKEN=$(oc whoami --show-token)
    export MLFLOW_WORKSPACE=<namespace>
    ```

=== "Kubernetes Plugin (RHOAI 3.4 EA1/EA2, Red Hat fork)"

    ```bash
    export MLFLOW_TRACKING_AUTH=kubernetes
    ```

    Reads credentials from the mounted service-account token (in-pod) or `~/.kube/config` (workstation).

=== "Built-in Plugin (MLflow SDK 3.11+, RHOAI 3.4 GA)"

    ```bash
    export MLFLOW_TRACKING_AUTH=kubernetes-namespaced
    ```

### Smoke Test

```python
import random
import time
import mlflow

mlflow.set_experiment("demo-experiment")

with mlflow.start_run(run_name="demo-run") as run:
    mlflow.log_param("model_type", "baseline")
    mlflow.log_param("feature_count", 3)
    for step in range(5):
        mlflow.log_metric("accuracy", 0.8 + random.random() * 0.2, step=step)
        mlflow.log_metric("loss", 0.5 - random.random() * 0.2, step=step)
        time.sleep(0.2)
```

## Workspaces

Workspaces are an upstream MLflow feature contributed by Red Hat for multi-tenancy. There is a **1:1 mapping** between Kubernetes namespaces and MLflow workspaces. The workspace name is the namespace name.

Set the active workspace in Python:

```python
import mlflow
mlflow.set_workspace("<namespace>")
```

Or via environment variable:

```bash
export MLFLOW_WORKSPACE=<namespace>
```

Namespace lifecycle is managed outside of MLflow -- creating, updating, or deleting a namespace through the MLflow API is not supported.

## Authorization

Every MLflow API request is authorized through a Kubernetes `SelfSubjectAccessReview`. The MLflow server takes the caller's bearer token and checks whether it is allowed to perform a given verb on a given resource in the target namespace.

The checked resources belong to the `mlflow.kubeflow.org` API group. These are **pseudo-resources** used solely for RBAC policy evaluation -- they are not CRDs and no corresponding objects exist on the cluster.

| Pseudo-resource | Controls access to |
|-----------------|-------------------|
| `experiments` | Experiments, runs, traces, logged models, scorers, jobs |
| `registeredmodels` | Registered models, model versions, prompts |
| `datasets` | Evaluation datasets, dataset records, dataset tags |
| `gatewayendpoints` | AI Gateway endpoint management (CRUD) |
| `gatewayendpoints/use` | AI Gateway endpoint invocation |

### RBAC for Service Accounts

For interactive users, the OpenShift `admin`, `edit`, and `view` roles already include the necessary permissions. For service accounts (RHOAI 3.4 EA2+), bind the `mlflow-integration` ClusterRole:

```bash
oc -n <namespace> create rolebinding my-component-mlflow \
  --clusterrole=mlflow-integration \
  --serviceaccount=<namespace>:<service-account-name>
```

See `components/instances/mlflow-instance/examples/mlflow-rolebinding.yaml` for a YAML example.

## Storage Backends

The default deployment uses SQLite + PVC for quick evaluation:

```yaml
spec:
  backendStoreUri: "sqlite:////mlflow/mlflow.db"
  artifactsDestination: "file:///mlflow/artifacts"
```

For production, use an external PostgreSQL database and S3-compatible object storage:

```yaml
spec:
  backendStoreUri: "postgresql://<user>:<password>@<host>:<port>/<database>"
  artifactsDestination: "s3://<bucket>/mlflow-artifacts"
```

## Disabled Features

The following MLflow features are currently disabled in this deployment:

- **AI Gateway** -- endpoint management and invocation are not available.
- **Automatic (Online) Quality Evaluation** -- under evaluation for enabling in a future release.

## Disable It

Set `mlflowoperator.managementState` to `Removed` in the DSC and delete the MLflow CR:

```bash
oc delete mlflow mlflow -n redhat-ods-applications
```
