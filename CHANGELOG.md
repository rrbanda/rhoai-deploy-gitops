# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed
- Repo restructured for multi-version support and portability
- Single `cluster-config.yaml` now drives all ArgoCD applications
- `configure.sh` rewritten with full parameterization support

## [3.5.0-ea2] — 2026-08-09

### Added
- RHOAI 3.5 EA2 support (DSC v2 API)
- AI Gateway with batch inference (Technology Preview)
- OGX (formerly LlamaStack) operator
- Models-as-a-Service (MaaS) with governance
- MLflow Operator
- Spark Operator
- Kubeflow Trainer
- LeaderWorkerSet (LWS) operator and instance
- Custom Metrics Autoscaler (KEDA) for WVA
- KServe Model Cache
- Hardware Profiles (infrastructure.opendatahub.io/v1)
- PostSync hook for gateway operator memory overrides
- MaaS DNS hairpin CronJob
- MaaS PostgreSQL StatefulSet
- EvalHub instance
- MCP Servers dashboard registration

### Changed
- DSC API upgraded from v1 to v2 (`datasciencecluster.opendatahub.io/v2`)
- Kueue operator channel: `stable-v1.2` → `stable-v1.4`
- Kueue `managementState` changed to `Unmanaged` (now managed by its own operator)
- Service Mesh operator: v2 → v3 (`servicemeshoperator3`)
- RHOAI operator channel: `fast` → `beta` (for EA access)
- HardwareProfile API group: `dashboard.opendatahub.io` → `infrastructure.opendatahub.io`
- `llamastackoperator` replaced by `ogx` (mutual exclusivity)
- GPU MachineSet moved to examples (cluster-specific)

### Fixed
- `batchGateway` null field error with ArgoCD sync (use `Replace=true`)
- Gateway operator OOM at default memory limits
- TrustyAI immutable selector during upgrade
- Dashboard config validation (removed deprecated fields)

## [3.4.0] — 2026-05-19

### Added
- Initial release with RHOAI 3.4 GA support
- Full GitOps deployment via ArgoCD ApplicationSets
- Composable DSC overlays (minimal, serving, training, full)
- GPU infrastructure (NFD, GPU Operator, MachineSets)
- Kueue integration for GPU scheduling
- KServe model serving
- Reference model deployments (Gemma, Qwen, GPT-OSS)
- Pre-commit hooks for secret scanning
- mkdocs documentation site

---

[Unreleased]: https://github.com/rrbanda/rhoai-deploy-gitops/compare/v3.5.0-ea2...HEAD
[3.5.0-ea2]: https://github.com/rrbanda/rhoai-deploy-gitops/compare/v3.4.0...v3.5.0-ea2
[3.4.0]: https://github.com/rrbanda/rhoai-deploy-gitops/releases/tag/v3.4.0
