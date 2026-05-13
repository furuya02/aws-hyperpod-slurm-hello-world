# aws-hyperpod-slurm-hello-world

A minimal example for spinning up an Amazon SageMaker HyperPod cluster (1 node) and running Slurm hello world plus a GPU recognition test.

## Cost warning (READ FIRST)

HyperPod **bills you for the entire time the cluster is running** (unlike Training Jobs, which bill per job).

| Item | Value |
|:--|:--|
| Instance | `ml.g5.2xlarge` × 1 node (A10G 24GB) |
| Pricing | On-Demand |
| 24 h idle cost | **~$53/day (~JPY 8,000/day)** |
| Recommended | create -> verify quickly -> run `scripts/teardown.sh` |

**Always run `scripts/teardown.sh` once you are done.**

## Resources

| Resource | Name |
|:--|:--|
| VPC | `aws-hyperpod-slurm-hello-world-vpc` (1 private subnet + 1 NAT Gateway) |
| IAM Role | `aws-hyperpod-slurm-hello-world-execution-role` |
| S3 Bucket | `aws-hyperpod-slurm-hello-world-<account-id>-lifecycle` |
| HyperPod cluster | `aws-hyperpod-slurm-hello-world` (1 InstanceGroup / 1 node / `ml.g5.2xlarge`) |

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

- AWS account with quota `ml.g5.2xlarge for cluster usage` >= 1 in `ap-northeast-1`
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

# 6. Create the cluster (ml.g5.2xlarge billing starts here)
cd ..
./scripts/create.sh
```

## Verify

```bash
# Connect via SSM Session Manager
./scripts/connect.sh

# On the node:
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
- The cluster runs Slurm controller + worker on the same node by aligning `provisioning_parameters.json#controller_group` with the InstanceGroup name `worker`

## License

MIT
