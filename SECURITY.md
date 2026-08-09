# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this repository, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, please report via [GitHub Issues](https://github.com/rrbanda/rhoai-deploy-gitops/issues) or use GitHub's private vulnerability reporting feature.

## Security Practices in This Repository

### No Real Secrets

This repository contains **no real secrets, credentials, or tokens**. All Secret YAML files use placeholder values (`CHANGE_ME`, example passwords for development databases, etc.).

### Pre-commit Scanning

We use [gitleaks](https://github.com/gitleaks/gitleaks) to scan every commit for accidentally committed secrets:

```bash
# Install pre-commit hooks
pip install pre-commit
pre-commit install
git config core.hooksPath .githooks
```

### What to Check Before Contributing

Before submitting a PR, verify:
- [ ] No real API keys, tokens, or passwords in your changes
- [ ] No `kubeconfig` files or cluster credentials
- [ ] No private SSH keys or certificates
- [ ] No `.env` files with real values

### Blocked File Patterns

The `.gitignore` blocks common sensitive file types:
- `*.pem`, `*.key`, `*.crt` — Certificates and keys
- `*.env`, `*.env.*` — Environment files
- `credentials.json` — Service account keys
- `kubeconfig`, `kubeconfig.*` — Cluster credentials

## Supported Versions

| Version | Supported |
|---------|-----------|
| main (latest) | ✅ |
| Tagged releases | ✅ |
| Archived branches | ❌ |
