#!/bin/bash
#
# HyperPod クラスタへの SSM 接続
#
# 使い方:
#   ./scripts/connect.sh
#
# 注意:
#   HyperPod ノードへの SSM ターゲットは EC2 の i-xxxx ではなく
#   "sagemaker-cluster:<cluster-id>_<instance-group-name>-<instance-id>" 形式。
#   i-xxxx をそのまま渡すと TargetNotConnected になる。
#

CLUSTER_NAME="aws-hyperpod-slurm-hello-world"
REGION="ap-northeast-1"

# 1. cluster-id を ClusterArn(.../cluster/<cluster-id>) の末尾から取り出す
CLUSTER_ID=$(aws sagemaker describe-cluster \
  --cluster-name "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --query 'ClusterArn' \
  --output text | awk -F/ '{print $NF}')

# 2. controller(Slurm ヘッドノード)の InstanceGroupName / InstanceId を取得
#    sinfo / sbatch は controller 上で実行するため、controller グループのノードに接続する
NODE=$(aws sagemaker list-cluster-nodes \
  --cluster-name "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --query 'ClusterNodeSummaries[?InstanceGroupName==`controller`]|[0].[InstanceGroupName,InstanceId]' \
  --output text)
INSTANCE_GROUP=$(echo "${NODE}" | cut -f1)
INSTANCE_ID=$(echo "${NODE}" | cut -f2)

# 3. HyperPod 専用フォーマットの SSM ターゲットで接続
aws ssm start-session \
  --target "sagemaker-cluster:${CLUSTER_ID}_${INSTANCE_GROUP}-${INSTANCE_ID}" \
  --region "${REGION}"
