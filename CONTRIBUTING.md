# Contributing

Contributions are welcome. This guide covers the conventions used in this repository so your changes integrate cleanly.

## Getting Started

1. **Fork** the repository and clone your fork
2. Run `./setup.sh --repo https://github.com/YOURORG/rhoai-deploy-gitops.git` to point all ArgoCD manifests at your fork
3. If deploying GPU workers on AWS, customize the MachineSets in `components/instances/gpu-workers/examples/aws/` with your cluster's infra ID, AMI, subnet, etc.

## Directory Conventions

```
components/
  operators/<name>/         Operator Subscription (auto-discovered by cluster-operators AppSet)
  instances/<name>/         Operator instance CR (auto-discovered by cluster-instances AppSet)

usecases/
  models/<name>/            Model serving manifests
    manifests/              ServingRuntime, InferenceService, PVC, download Job, etc.
    profiles/tier1-minimal/ Kustomize overlay (auto-discovered by cluster-models AppSet)
  services/<name>/          Application service manifests
    manifests/              Namespace, RBAC, Deployments, Routes, etc.
    profiles/tier1-minimal/ Kustomize overlay (auto-discovered by cluster-services AppSet)
```

ArgoCD auto-discovers any directory matching these patterns. Adding a new directory and pushing to Git is all that's needed to deploy.

## Adding a New Model

1. Create `usecases/models/<name>/manifests/` with at minimum:
   - `kustomization.yaml`, `namespace.yaml`, `serving-runtime.yaml`, `inference-service.yaml`
2. Create `usecases/models/<name>/profiles/tier1-minimal/kustomization.yaml` referencing the manifests
3. Push to Git -- the `cluster-models` ApplicationSet creates a `model-<name>` Application

See existing models (`orchestrator-8b`, `qwen-math-7b`, `gpt-oss-120b`) for working examples.

## Adding a New Service

1. Create `usecases/services/<name>/manifests/base/` with namespace and RBAC
2. Add service-specific manifests under `manifests/`
3. Create `usecases/services/<name>/profiles/tier1-minimal/kustomization.yaml`
4. Push to Git -- the `cluster-services` ApplicationSet creates a `service-<name>` Application

See the [Use Cases documentation](https://rrbanda.github.io/rhoai-deploy-gitops/usecases/) for details.

## Pull Request Guidelines

- **Test before submitting** -- Verify your manifests work with `oc apply -k` (dry-run or on a test cluster)
- **Follow the 4-phase ordering** -- Operators before instances, instances before DSC, DSC before use cases
- **Use sync waves** -- PVCs at wave -1, download Jobs at wave 0, InferenceServices at wave 1
- **No secrets in Git** -- Use placeholder values and document what needs to be changed
- **Keep docs in sync** -- If you add a model or service, update `docs/usecases/index.md` and `usecases/README.md`

## Documentation

The docs site is built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/) and deployed to GitHub Pages on pushes to `main` that touch `docs/` or `mkdocs.yml`.

To preview locally:

```bash
pip install mkdocs-material
mkdocs serve
```

## License

This project is licensed under the [Apache License 2.0](LICENSE).
