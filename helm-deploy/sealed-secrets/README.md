# Sealed Secrets Workflow

This directory contains templates for creating Kubernetes secrets sealed with
[Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets).

## Overview

Sealed Secrets allow you to encrypt secrets so they can be safely stored in Git.
Only the Sealed Secrets controller running in the cluster can decrypt them.

## Workflow

1. **Install kubeseal CLI** (if not already installed):
   ```bash
   brew install kubeseal   # macOS
   ```

2. **Create a plain Secret** from the template:
   ```bash
   cp registry-secret.yaml.template registry-secret.yaml
   # Edit registry-secret.yaml with actual credentials
   ```

3. **Seal the Secret** using the cluster's public key:
   ```bash
   kubeseal --format yaml \
     --controller-namespace sealed-secrets \
     < registry-secret.yaml \
     > registry-sealed-secret.yaml
   ```

4. **Commit the SealedSecret** (NOT the plain secret):
   ```bash
   git add registry-sealed-secret.yaml
   git commit -m "Add sealed registry credentials"
   ```

5. **Apply** via ArgoCD or directly:
   ```bash
   oc apply -f registry-sealed-secret.yaml
   ```

## Notes

- **NEVER** commit plain-text secrets to Git.
- The sealed secret can only be decrypted by the specific cluster where the
  controller is running.
- Registry credentials are NOT needed for chart deployment since the chart
  is stored in Git. They are only required if your cluster needs to pull
  container images from `registry.redhat.io` without a global pull secret.
- If the cluster already has a global pull secret configured for
  `registry.redhat.io`, you do not need this sealed secret at all.
