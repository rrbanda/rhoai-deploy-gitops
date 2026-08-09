# GPU Workers

This directory manages GPU MachineSet resources for the cluster.

## Setup for a new cluster

1. Export an existing GPU MachineSet from your cluster:
   ```bash
   oc get machineset -n openshift-machine-api -o yaml <your-gpu-machineset>
   ```

2. Or create one from the examples in `examples/aws/`.

3. Place the resulting `gpu-machineset.yaml` in this directory.

4. Adjust `replicas` to control GPU node count (0 = scaled down).

## Important fields to customize per cluster

- `metadata.name` — must match `<cluster-infra-id>-worker-gpu-<az>`
- `machine.openshift.io/cluster-api-cluster` labels — must match cluster infra ID
- `spec.template.spec.providerSpec.value.ami.id` — must match cluster's CoreOS AMI
- `spec.template.spec.providerSpec.value.iamInstanceProfile.id` — must match cluster's worker IAM profile
- `spec.template.spec.providerSpec.value.placement` — region and AZ
- `spec.template.spec.providerSpec.value.securityGroups` — cluster-specific SG
- `spec.template.spec.providerSpec.value.subnet` — cluster-specific subnet
