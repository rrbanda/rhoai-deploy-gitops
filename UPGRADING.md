# Upgrading RHOAI Version

This document describes the steps to upgrade this repository to a new RHOAI version (e.g., from 3.4 to 3.5).

## Version-Dependent Files

### 1. Operator Channel (single place)

The RHOAI operator channel is set in one file:

```
components/operators/rhoai-operator/patch-channel.yaml
```

Change the `value` field to the desired channel (e.g., `fast-3.x`, `stable-3.5`, `eus-3.6`).

### 2. vLLM Serving Runtime Image (per-model kustomization)

Each model's `manifests/kustomization.yaml` has an `images` transformer that pins the vLLM tag:

```
usecases/models/gpt-oss-120b/manifests/kustomization.yaml
usecases/models/orchestrator-8b/manifests/kustomization.yaml
usecases/models/qwen-math-7b/manifests/kustomization.yaml
```

Update the `newTag` field under `images` to match the new RHOAI vLLM image version.

### 3. DataScienceCluster Spec

New RHOAI versions may add components to the DSC spec. Check the release notes and update:

```
components/instances/rhoai-instance/base/datasciencecluster.yaml
components/instances/rhoai-instance/overlays/*/datasciencecluster.yaml
```

### 4. DSCInitialization Spec

New monitoring or observability fields may be added:

```
components/instances/rhoai-instance/base/dscinitalization.yaml
```

### 5. Documentation References

Search and replace version strings across docs:

```bash
grep -rl '3\.4' docs/ README.md CONTRIBUTING.md | head -20
```

### 6. NFD Operand Image

```
components/instances/nfd-instance/nodefeaturediscovery.yaml
```

Update the image tag to match the new OCP version if it changes.

## Upgrade Checklist

- [ ] Update `patch-channel.yaml` channel value
- [ ] Update vLLM `newTag` in each model's `kustomization.yaml`
- [ ] Review DSC component changes in the new version's release notes
- [ ] Update DSCInitialization if new fields are added
- [ ] Update NFD image tag if OCP version changes
- [ ] Update documentation version references
- [ ] Test with `oc kustomize` to validate all overlays render correctly
- [ ] Push to a non-production branch and verify ArgoCD sync
