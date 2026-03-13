# GPU Worker Nodes

GPU node provisioning is **cloud-provider specific**. This directory contains no default resources -- you must configure GPU workers for your environment.

## AWS

Example MachineSets for AWS are in `examples/aws/`. Before applying, you **must** edit these files to match your cluster:

| Value | Where to find it |
|-------|-------------------|
| Cluster infrastructure ID (e.g. `ocp-2qkbk`) | `oc get -o jsonpath='{.status.infrastructureName}' infrastructure cluster` |
| AMI ID | `oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.ami.id}'` |
| Region and AZ | `oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.placement.region}'` |
| Subnet, security groups, IAM profile | Copy from an existing worker MachineSet in your cluster |

Then apply:

```bash
oc apply -k examples/aws/
```

## Azure / GCP / Bare Metal

Create your own MachineSets or provision GPU nodes manually. The only requirement is that nodes have NVIDIA GPUs and the GPU Operator installed (handled by `components/operators/gpu-operator/`).

If using bare metal or pre-provisioned nodes, no MachineSets are needed -- just ensure the nodes are labeled and joined to the cluster.
