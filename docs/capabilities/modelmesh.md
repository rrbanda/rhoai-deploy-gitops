# ModelMesh Multi-Model Serving

ModelMesh enables efficient multi-model serving by packing multiple models into shared serving pods. Use ModelMesh when you need to serve many smaller models cost-effectively with shared GPU resources, rather than dedicating a full pod per model as KServe does.

!!! warning "v2 DSC API change"
    In the RHOAI 3.4 v2 DSC API, ModelMesh has been replaced by `modelsAsService` under `kserve`. The serving overlay does **not** enable ModelMesh. If you need multi-model serving, configure `kserve.modelsAsService.managementState: Managed` in your DSC.

## Dependencies

| Requirement | Type | Path |
|-------------|------|------|
| RHOAI Operator | Operator | `components/operators/rhoai-operator/` |
| DSC `kserve.modelsAsService: Managed` | DSC component | `components/instances/rhoai-instance/` |
| GPU Infrastructure (optional) | Operator + Instance | See [gpu-infrastructure.md](gpu-infrastructure.md) |

ModelMesh does not require cert-manager or Knative -- it uses its own routing.

## Enable It

=== "DSC Patch"

    ```yaml
    spec:
      components:
        kserve:
          modelsAsService:
            managementState: Managed
    ```

## Deploy

=== "GitOps"

    ModelMesh is enabled automatically when the `rhoai-instance` ArgoCD Application points to the `serving`, `full`, or `dev` overlay.

=== "Manual"

    ```bash
    # 1. Install the RHOAI operator
    oc apply -k components/operators/rhoai-operator/
    oc get csv -A | grep rhods

    # 2. Create DSC with serving overlay
    oc apply -k components/instances/rhoai-instance/overlays/serving/

    # 3. Wait for DSC
    oc wait --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True \
      datasciencecluster/default-dsc --timeout=600s
    ```

## Verify

```bash
# ModelMesh controller should be running
oc get pods -n redhat-ods-applications -l app=modelmesh-controller
```

## Example: Deploy a Model with ModelMesh

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: my-sklearn-model
  namespace: my-namespace
  annotations:
    serving.kserve.io/deploymentMode: ModelMesh
spec:
  predictor:
    model:
      modelFormat:
        name: sklearn
      storageUri: "s3://my-bucket/sklearn-model"
```

The key difference from KServe is `serving.kserve.io/deploymentMode: ModelMesh`,
which routes the model to the shared ModelMesh pool instead of creating a
dedicated pod.

## When to Use ModelMesh vs KServe

| Factor | KServe | ModelMesh |
|--------|--------|-----------|
| Model isolation | Dedicated pod per model | Shared pod pool |
| Scale-to-zero | Yes (via Knative) | No |
| GPU efficiency | One GPU per model | Multiple models per GPU |
| Best for | LLMs, large models | Many small/medium models |
| Protocol | OpenAI-compatible (vLLM) | gRPC / REST |

## Disable It

Set `kserve.modelsAsService.managementState` to `Removed` in the DSC.
