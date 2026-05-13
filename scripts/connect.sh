#!/bin/bash
#
# HyperPod クラスタへの SSM 接続
#
# 使い方:
#   ./scripts/connect.sh
#

CLUSTER_NAME="aws-hyperpod-slurm-hello-world"
REGION="ap-northeast-1"

# 1 ノード構成なので最初のノードに接続
NODE_ID=$(aws sagemaker list-cluster-nodes \
  --cluster-name "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --query 'ClusterNodeSummaries[0].InstanceId' \
  --output text)

aws ssm start-session --target "${NODE_ID}" --region "${REGION}"
