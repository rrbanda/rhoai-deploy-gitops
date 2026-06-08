# Use Cases

Models, services, and training workloads are managed in the companion repository:

**[rhoai-usecases](https://github.com/rrbanda/rhoai-usecases)**

This separation keeps platform deployment independent from workload lifecycle.

The companion repo includes:

- **Models**: gpt-oss-120b, orchestrator-8b, qwen-math-7b (KServe + vLLM)
- **Services**: LlamaStack, GenAI Toolbox, Red Hat OKP, ToolOrchestra
- **Training**: GRPO reinforcement learning workloads
- **ArgoCD**: Self-contained ApplicationSets and AppProject for use cases
