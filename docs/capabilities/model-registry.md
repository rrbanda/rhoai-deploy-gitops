# Model Registry

The Model Registry provides a central catalog for tracking ML model versions, metadata, and artifacts. Use it when you need governance over which models are deployed, version history, and programmatic access to model metadata across your organization.

## Dependencies

| Requirement | Type | Path |
|-------------|------|------|
| RHOAI Operator | Operator | `components/operators/rhoai-operator/` |
| DSC `modelregistry: Managed` | DSC component | `components/instances/rhoai-instance/` |
| External MySQL database (5.x or later, 8.x recommended) | External service | Provisioned outside the cluster |
| S3-compatible object storage | External service | Provisioned outside the cluster |

!!! warning "External database and storage required"
    The official RHOAI 3.3 documentation requires an external MySQL database (version 5.x or later, 8.x recommended) and S3-compatible object storage for Model Registry. These are **not** provisioned by the RHOAI Operator -- you must set them up before enabling this component. Model Registry does not require GPU infrastructure.

## Enable It

Model Registry is enabled in the `dev` and `full` overlays.

=== "DSC Patch"

    ```yaml
    spec:
      components:
        modelregistry:
          managementState: Managed
    ```

## Deploy

=== "GitOps"

    Model Registry is enabled automatically when the `rhoai-instance` ArgoCD Application points to the `full` or `dev` overlay.

=== "Manual"

    ```bash
    # 1. Install the RHOAI operator
    oc apply -k components/operators/rhoai-operator/
    oc get csv -A | grep rhods

    # 2. Create DSC with model registry enabled
    oc apply -k components/instances/rhoai-instance/overlays/dev/

    # 3. Wait for DSC
    oc wait --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True \
      datasciencecluster/default-dsc --timeout=600s
    ```

## Verify

```bash
# Model Registry operator pods
oc get pods -n redhat-ods-applications -l app=model-registry-operator

# Check the model registry namespace
oc get pods -n rhoai-model-registries
```

## Usage

1. Open the RHOAI Dashboard
2. Navigate to **Model Registry**
3. Register models with version metadata, artifact URIs, and custom properties
4. Deploy registered models directly to KServe or ModelMesh from the UI

### Programmatic access

Use the Model Registry REST API or the Python `model-registry` SDK:

```python
from model_registry import ModelRegistry

registry = ModelRegistry(
    server_address="https://model-registry-route",
    author="data-scientist",
)

model = registry.register_model(
    "my-model",
    uri="s3://bucket/model.onnx",
    version="1.0.0",
    model_format_name="onnx",
)
```

## Disable It

Set `modelregistry.managementState` to `Removed` in the DSC.
