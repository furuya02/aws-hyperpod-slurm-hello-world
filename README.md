# aws-hyperpod-slurm-hello-world

A minimal example for spinning up an Amazon SageMaker HyperPod cluster (2 nodes: controller + worker) with FSx for Lustre shared storage and a Data Repository Association (DRA) that auto-syncs `/fsx/jobs` ↔ S3. Runs Slurm hello world + GPU recognition test + `/fsx` mount verification + S3 auto-export check.

## Cost warning (READ FIRST)

HyperPod **bills you for the entire time the cluster is running** (unlike Training Jobs, which bill per job). FSx for Lustre also bills separately by the second. DRA itself is free.

| Item | Value |
|:--|:--|
| Instances | controller `ml.c5.xlarge` × 1 + worker `ml.g5.2xlarge` × 1 (A10G 24GB) |
| Shared storage | FSx for Lustre PERSISTENT_2 SSD, 1.2 TiB, 125 MB/s/TiB, **Lustre 2.15** |
| S3 sync | DRA: `/fsx/jobs` ↔ `s3://...-lifecycle/jobs/` (AutoImport/AutoExport: NEW, CHANGED, DELETED) |
| Pricing | On-Demand |
| 24 h idle cost | **~$68/day (~JPY 10,200/day)** (worker ~$53 + controller ~$6 + FSx ~$8 + NAT ~$1.5) |
| Recommended | create → verify quickly → run `scripts/teardown.sh` |

**Always run `scripts/teardown.sh` once you are done.** Deletion order is critical: cluster → DRA → FSx → CDK stack. `teardown.sh` enforces this automatically.

## Resources

| Resource | Name |
|:--|:--|
| VPC | `aws-hyperpod-slurm-hello-world-vpc` (1 private subnet + 1 NAT Gateway) |
| IAM Role | `aws-hyperpod-slurm-hello-world-execution-role` |
| S3 Bucket | `aws-hyperpod-slurm-hello-world-<account-id>-lifecycle` (used for lifecycle scripts AND DRA target) |
| FSx Security Group | `aws-hyperpod-slurm-hello-world-fsx-sg` (Lustre ports 988, 1021-1023) |
| FSx for Lustre | `aws-hyperpod-slurm-hello-world-fsx` (created by `scripts/create-fsx.sh`, not CDK; Lustre 2.15 explicit) |
| FSx DRA | `/fsx/jobs` ↔ `s3://aws-hyperpod-slurm-hello-world-<account-id>-lifecycle/jobs/` (created by `scripts/create-fsx.sh`) |
| HyperPod cluster | `aws-hyperpod-slurm-hello-world` (2 InstanceGroups: controller `ml.c5.xlarge` × 1 / worker `ml.g5.2xlarge` × 1) |

## Layout

```
.
├── cdk/                          # AWS CDK (TypeScript): VPC / IAM / S3 / FsxSg + S3 bucket policy for FSx
├── lifecycle/                    # Per-node bootstrap files
│   ├── README.md
│   ├── provisioning_parameters.json   # version + worker_groups + controller_group + <FSX_*> placeholders
│   └── config.py.override
│   # The rest comes from scripts/sync-lifecycle.sh (awslabs/awsome-distributed-ai base-config)
├── scripts/
│   ├── sync-lifecycle.sh         # pull lifecycle scripts from awslabs/awsome-distributed-ai
│   ├── create-fsx.sh             # create FSx for Lustre + DRA (15-30 min total)
│   ├── create.sh                 # create cluster (cluster billing starts)
│   ├── connect.sh                # SSM Session Manager connect (to controller)
│   ├── delete-cluster.sh         # delete cluster only (for repeated tests)
│   ├── delete-fsx.sh             # delete DRA -> FSx for Lustre (in that order)
│   └── teardown.sh               # cluster -> DRA -> FSx -> cdk destroy (full cleanup, ordered)
├── jobs/
│   ├── hello.py                  # PyTorch-free (hostname + /fsx + nvidia-smi via subprocess)
│   └── hello.sh                  # sbatch with --output=/fsx/jobs/...
├── cluster-config.json
├── README.md
└── README.ja.md
```

## Prerequisites

- AWS account with quotas in `ap-northeast-1`:
  - HyperPod cluster: `ml.g5.2xlarge for cluster usage` >= 1 (worker) and `ml.c5.xlarge for cluster usage` >= 1 (controller)
  - FSx for Lustre: SSD storage capacity quota >= 1228 GiB (1.2 TiB)
- Local tools: `aws` CLI, `pnpm`, Node.js 20+, `git`, `jq`, Python 3, Session Manager plugin
- AWS credentials configured

## Build / deploy

```bash
# 1. Clone
git clone https://github.com/furuya02/aws-hyperpod-slurm-hello-world.git
cd aws-hyperpod-slurm-hello-world

# 2. Pull lifecycle scripts (from awslabs/awsome-distributed-ai)
./scripts/sync-lifecycle.sh

# 3. Install CDK deps
cd cdk
pnpm install

# 4. Bootstrap (first time only)
pnpm cdk bootstrap

# 5. Deploy VPC / IAM / S3 / FsxSg + S3 bucket policy for FSx
#    (NAT billing starts here, ~JPY 220/day)
pnpm cdk deploy

# 6. Create FSx for Lustre + DRA (~15-30 min total)
#    (FSx billing starts: ~JPY 1,200/day on top, total ~JPY 1,400/day with NAT)
cd ..
./scripts/create-fsx.sh

# 7. Create the cluster (cluster billing starts: total ~JPY 10,200/day)
./scripts/create.sh
```

## Verify

```bash
# Connect via SSM Session Manager (connects to the controller node)
./scripts/connect.sh

# On the controller node (srun dispatches to the worker):
sinfo
srun -N1 hostname
srun -N1 nvidia-smi

# FSx for Lustre mount verification
mount | grep fsx
srun -N1 bash -c 'mount | grep fsx'
mkdir -p /fsx/jobs
echo "hello" > /fsx/jobs/test.txt
srun -N1 cat /fsx/jobs/test.txt  # should print "hello" (shared across nodes)

# DRA auto-export to S3 (visible after a few seconds to minutes)
aws s3 ls s3://aws-hyperpod-slurm-hello-world-<ACCOUNT_ID>-lifecycle/jobs/

# Run hello job (place hello.py / hello.sh in /fsx/jobs/ first)
# Note: sbatch stdout may be empty in some cases; srun is the reliable path
srun -N1 python3 /fsx/jobs/hello.py
```

## Tear down (required)

```bash
./scripts/teardown.sh
```

`teardown.sh` runs in the correct order:

1. `delete-cluster.sh` — waits for HyperPod cluster deletion to complete (~10-15 min)
2. `delete-fsx.sh` — deletes DRA first, then FSx for Lustre (~25-45 min total)
3. `pnpm cdk destroy --all --force` — VPC / NAT / IAM / S3 / FsxSg (~3-5 min)

Ordering is critical:

- Deleting FSx before the cluster fails (the cluster has the FSx mounted)
- Deleting FSx before its DRA fails (DRA still references it)
- Deleting the VPC before FSx leaves ENIs and prevents NAT deletion (billing keeps running)

After it finishes, confirm in AWS Cost Explorer that SageMaker / EC2 / FSx charges drop to $0 the next day.

## Notes

- Error handling is intentionally minimal; this is a learning sample, not production code
- Files brought in by `scripts/sync-lifecycle.sh` under `lifecycle/` are git-ignored
- The cluster splits Slurm roles across two nodes: controller on `ml.c5.xlarge`, compute (worker) on `ml.g5.2xlarge`. `lifecycle_script.py` decides a node's role by matching its InstanceGroup name against `provisioning_parameters.json#controller_group` (exclusive: match → controller, otherwise → compute), so both roles cannot live in one InstanceGroup.
- FSx for Lustre + DRA is intentionally **outside** CDK so users can observe the 3-stage cost progression (VPC+NAT → +FSx → +Cluster). The trade-off is forgetting to delete FSx leaks ~JPY 1,200/day; `teardown.sh` mitigates this with ordered deletion.
- DRA setup is done via AWS CLI (`aws fsx create-data-repository-association`) instead of kit's Lambda Custom Resource. Same underlying API, lighter implementation. Trade-off: no automatic stack-update reconciliation.
- Source lifecycle repo: `awslabs/awsome-distributed-ai` (renamed/transferred from `aws-samples/awsome-distributed-training` in May 2026).
- HyperPod DLAMI does **not** include PyTorch / Python ML frameworks. Only NVIDIA driver + CUDA. The included `hello.py` is therefore PyTorch-free (`nvidia-smi` via subprocess).

## License

MIT
