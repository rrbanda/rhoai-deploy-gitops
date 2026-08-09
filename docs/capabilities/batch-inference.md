# Batch Inference

Batch inference processes large volumes of requests asynchronously, optimizing for throughput rather than latency. RHOAI 3.5 introduces the **Batch Gateway** powered by llm-d, which queues inference requests and processes them efficiently using available GPU capacity.

## When to Use Batch vs. Real-Time

| Characteristic | Real-Time (KServe) | Batch (Batch Gateway) |
|---------------|-------------------|----------------------|
| **Latency target** | Milliseconds to seconds | Minutes to hours |
| **Use case** | Chat, interactive apps | Document processing, evaluations, bulk scoring |
| **Scaling model** | Scale up replicas immediately | Queue requests, process when GPUs available |
| **Cost optimization** | Pays for idle capacity | Maximizes GPU utilization |
| **Request volume** | Low to moderate, steady | High volume, bursty |

**Use batch inference when:**

- You have thousands of documents to process overnight
- You are running model evaluations across large datasets
- You want to maximize GPU utilization during off-peak hours
- Latency is not critical (results within hours, not seconds)

## Architecture

```mermaid
graph LR
  subgraph clients ["Clients"]
    App1["Application 1"]
    App2["Application 2"]
    App3["Batch Job"]
  end

  subgraph gateway ["Batch Gateway"]
    Queue["Request Queue"]
    Scheduler["Batch Scheduler"]
    AIGateway["AI Gateway (routing)"]
  end

  subgraph inference ["Inference Backend"]
    LLMd["llm-d Workers"]
    GPU1["GPU Pod 1"]
    GPU2["GPU Pod 2"]
    GPU3["GPU Pod 3"]
  end

  App1 -->|"submit batch"| Queue
  App2 -->|"submit batch"| Queue
  App3 -->|"submit batch"| Queue
  Queue --> Scheduler
  Scheduler --> AIGateway
  AIGateway --> LLMd
  LLMd --> GPU1
  LLMd --> GPU2
  LLMd --> GPU3
```

## Dependencies

| Requirement | Type | Purpose |
|-------------|------|---------|
| RHOAI Operator | Operator | Core platform |
| cert-manager | Operator | TLS for internal communication |
| ServiceMesh 3 | Operator | Service routing for batch gateway |
| LeaderWorkerSet (LWS) | Operator | Leader-worker topology for llm-d |
| DSC `batchGateway: Managed` | DSC component | Enables batch inference |

## Enable It

Set `batchGateway.managementState` to `Managed` in your DSC:

```yaml
spec:
  components:
    batchGateway:
      managementState: Managed
```

This is already enabled in the `full`, `dev`, and `maas` overlays.

## Deploy

=== "GitOps"

    Batch inference is enabled automatically when using the `full` or `maas` DSC overlay. The required operators (ServiceMesh, LWS) are installed via the `cluster-operators` ApplicationSet.

=== "Manual"

    ```bash
    # 1. Install required operators
    oc apply -k components/operators/cert-manager/
    oc apply -k components/operators/servicemesh/
    oc apply -k components/operators/lws-operator/
    oc apply -k components/operators/rhoai-operator/

    # 2. Wait for operators
    watch "oc get csv -A | grep -E 'cert-manager|servicemesh|lws|rhods'"

    # 3. Deploy DSC with batch gateway enabled
    oc apply -k components/instances/rhoai-instance/overlays/full/
    ```

## Verify

```bash
# AI Gateway operator running
oc get pods -n redhat-ods-applications -l app=ai-gateway-operator

# Batch gateway controller running
oc get pods -n redhat-ods-applications -l app=llm-d-batch-gateway-operator

# Check DSC component status
oc get datasciencecluster default-dsc -o jsonpath='{.status.components.batchGateway}'
```

## How It Works

1. **Client submits a batch** -- A set of prompts/requests sent to the batch endpoint
2. **Gateway queues requests** -- The AI Gateway accepts and queues them
3. **Scheduler optimizes** -- llm-d batches requests for optimal GPU utilization (continuous batching)
4. **Workers process** -- GPU pods process batches in parallel
5. **Results collected** -- Responses are gathered and returned to the client

The batch gateway uses **continuous batching** -- new requests are added to in-flight batches as previous tokens complete, maximizing GPU memory and compute utilization.

## Known Considerations

!!! warning "Memory requirements"
    The AI Gateway operator and llm-d batch gateway controller may need elevated memory limits. The GitOps manifests include a PostSync hook that patches memory to 1Gi and 512Mi respectively. If you see OOMKilled pods, check the memory limits on these deployments.

!!! info "ServiceMesh 3 required"
    Batch gateway uses ServiceMesh 3 (Istio-based) for request routing. This is a different operator from the deprecated ServiceMesh 2.x. Ensure `servicemeshoperator3` (not `servicemeshoperator`) is installed.
