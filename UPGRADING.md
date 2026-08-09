# Upgrading

For the complete RHOAI upgrade guide, see the documentation site:

**[Upgrade Guide](docs/upgrading.md)**

Quick reference:

1. Update the operator channel in `components/operators/rhoai-operator/patch-channel.yaml`
2. Add any new operators required by the target version
3. Run `kustomize build` to verify manifests
4. Commit, push, and let ArgoCD reconcile

For version-specific migration steps, channel guidance, and rollback procedures, see the full guide linked above.
