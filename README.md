# aws-hyperpod-slurm-hello-world

A minimal example for spinning up an Amazon SageMaker HyperPod cluster (2 nodes: controller + worker) and running Slurm hello world plus a GPU recognition test.

## Cost warning (READ FIRST)

HyperPod **bills you for the entire time the cluster is running** (unlike Training Jobs, which bill per job).

| Item | Value |
|:--|:--|
| Instances | controller `ml.c5.xlarge` × 1 + worker `ml.g5.2xlarge` × 1 (A10G 24GB) |
| Pricing | On-Demand |
| 24 h idle cost | **~$59/day (~JPY 8,800/day)** (worker ~$53 + controller ~$6) |
| Recommended | create -> verify quickly -> run `scripts/teardown.sh` |

**Always run `scripts/teardown.sh` once you are done.**

## Resources

| Resource | Name |
|:--|:--|
| VPC | `aws-hyperpod-slurm-hello-world-vpc` (1 private subnet + 1 NAT Gateway) |
| IAM Role | `aws-hyperpod-slurm-hello-world-execution-role` |
| S3 Bucket | `aws-hyperpod-slurm-hello-world-<account-id>-lifecycle` |
| HyperPod cluster | `aws-hyperpod-slurm-hello-world` (2 InstanceGroups: controller `ml.c5.xlarge` × 1 / worker `ml.g5.2xlarge` × 1) |

## Layout

```
.
├── cdk/                          # AWS CDK (TypeScript)
├── lifecycle/                    # Per-node bootstrap files
│   ├── README.md
│   ├── provisioning_parameters.json
│   └── config.py.override
│   # The rest comes from scripts/sync-lifecycle.sh (AWS Samples base-config)
├── scripts/
│   ├── sync-lifecycle.sh         # pull AWS Samples lifecycle into lifecycle/
│   ├── create.sh                 # create cluster (billing starts)
│   ├── connect.sh                # SSM Session Manager connect
│   └── teardown.sh               # wait for cluster deletion + cdk destroy
├── jobs/
│   ├── hello.py
│   └── hello.sh
├── cluster-config.json
├── README.md
└── README.ja.md
```

## Prerequisites

- AWS account with HyperPod cluster quotas in `ap-northeast-1`: `ml.g5.2xlarge for cluster usage` >= 1 (worker) and `ml.c5.xlarge for cluster usage` >= 1 (controller)
- Local tools: `aws` CLI, `pnpm`, Node.js 20+, `git`, `jq`, Python 3, Session Manager plugin
- AWS credentials configured

## Build / deploy

```bash
# 1. Clone
git clone https://github.com/furuya02/aws-hyperpod-slurm-hello-world.git
cd aws-hyperpod-slurm-hello-world

# 2. Pull AWS Samples lifecycle scripts
./scripts/sync-lifecycle.sh

# 3. Install CDK deps
cd cdk
pnpm install

# 4. Bootstrap (first time only)
pnpm cdk bootstrap

# 5. Deploy VPC / IAM / S3 (NAT Gateway billing starts here until cdk destroy)
pnpm cdk deploy
# Override the bucket suffix if you prefer:
# pnpm cdk deploy -c bucket_suffix=20260514

# 6. Create the cluster (HyperPod 2-node billing starts here: ~$59/day total)
cd ..
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

# Dummy Python job
sbatch /path/to/hello.sh
squeue
cat hello.*.out
```

## Tear down (required)

```bash
./scripts/teardown.sh
```

- Waits for cluster deletion to complete, then destroys the CDK stack (NAT Gateway included)
- After it finishes, confirm in AWS Cost Explorer that SageMaker / EC2 charges drop to $0 the next day

## Notes

- Error handling is intentionally minimal; this is a learning sample, not production code
- Files brought in by `scripts/sync-lifecycle.sh` under `lifecycle/` are git-ignored
- The cluster splits Slurm roles across two nodes: controller on `ml.c5.xlarge`, compute (worker) on `ml.g5.2xlarge`. `lifecycle_script.py` decides a node's role by matching its InstanceGroup name against `provisioning_parameters.json#controller_group` (exclusive: match -> controller, otherwise -> compute), so both roles cannot live in one InstanceGroup.

## License

MIT
