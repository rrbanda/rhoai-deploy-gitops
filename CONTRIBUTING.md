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
```

ArgoCD auto-discovers any directory matching these patterns. Adding a new directory and pushing to Git is all that's needed to deploy.

## Adding Models or Services

Model deployments, application services, and training workloads are managed in the **[rhoai-usecases](https://github.com/rrbanda/rhoai-usecases)** companion repository. Please contribute models and services there.

## Pull Request Guidelines

- **Test before submitting** -- Verify your manifests work with `oc apply -k` (dry-run or on a test cluster)
- **Follow the 3-phase ordering** -- Operators before instances, instances before DSC
- **No secrets in Git** -- Use placeholder values and document what needs to be changed
- **Keep docs in sync** -- Update documentation when adding operators or instances

## Documentation

The docs site is built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/) and deployed to GitHub Pages on pushes to `main` that touch `docs/` or `mkdocs.yml`.

To preview locally:

```bash
pip install mkdocs-material
mkdocs serve
```

## License

This project is licensed under the [Apache License 2.0](LICENSE).
