# Use Cases

Each subdirectory contains a self-contained AI application deployment.

## Structure

```
usecases/
└── <app-name>/
    ├── manifests/
    │   ├── base/          # Namespace, RBAC, config, storage, network
    │   ├── serving/       # ServingRuntimes + InferenceServices (one dir per model)
    │   └── services/      # Application services (deployments, routes)
    └── profiles/
        ├── tier1-minimal/ # Kustomize overlay (ArgoCD or oc apply -k targets this)
        ├── tier2-standard/
        └── tier3-full/
```

## Adding a New Use Case

1. Create a new directory: `usecases/my-app/`
2. Add `manifests/base/` with at least a `kustomization.yaml` and `namespace.yaml`
3. Add model serving under `manifests/serving/<model-name>/`
4. Add application services under `manifests/services/<service-name>/`
5. Create at least one profile under `profiles/` that references the manifests
6. The `cluster-usecases-appset` ApplicationSet auto-discovers `profiles/tier1-minimal/`

## Manual Deployment

```bash
oc apply -k usecases/my-app/profiles/tier1-minimal/
```

## Current Use Cases

- **toolorchestra** -- NVIDIA ToolOrchestra multi-model orchestrator with specialist routing
