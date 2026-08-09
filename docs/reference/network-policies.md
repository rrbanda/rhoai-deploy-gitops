# Network Policies

By default, this repository does not include NetworkPolicies for model and service namespaces. In production environments, you should add default-deny ingress policies and explicitly allow only required traffic.

## Default Deny Template

Add this to any model or service namespace:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

## Allow Inference Traffic

For model serving endpoints (KServe InferenceServices):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-inference
spec:
  podSelector:
    matchLabels:
      component: predictor
  ingress:
    - ports:
        - port: 8080
          protocol: TCP
        - port: 8443
          protocol: TCP
  policyTypes:
    - Ingress
```

## Adding to a Deployment

Include the NetworkPolicy YAML in your model or service `manifests/` directory and reference it in the `kustomization.yaml`:

```yaml
resources:
  - namespace.yaml
  - serving-runtime.yaml
  - inference-service.yaml
  - network-policy.yaml   # Add this
```
