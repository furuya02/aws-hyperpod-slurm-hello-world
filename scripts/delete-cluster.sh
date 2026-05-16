#!/bin/bash
#
# HyperPod クラスタのみを削除する(VPC / NAT / IAM / S3 は残す)
#
# 用途:
#   動作確認のために「クラスタ作成 → 削除」を繰り返したいとき。
#   CDK スタック(VPC/NAT/IAM/S3)を残すので、再度 ./scripts/create.sh するだけで
#   クラスタを作り直せる(cluster-config.json の編集も不要)。
#   全工程が終わったら ./scripts/teardown.sh で CDK スタックごと削除する。
#
# 使い方:
#   ./scripts/delete-cluster.sh
#
# 重要:
#   delete-cluster は非同期。クラスタが完全に消える前に次の操作へ進むと
#   ENI 残留などの原因になるため、本スクリプトは削除完了まで待機する。
#

CLUSTER_NAME="aws-hyperpod-slurm-hello-world"
REGION="ap-northeast-1"

# 1. HyperPod クラスタ削除要求(非同期)
aws sagemaker delete-cluster --cluster-name "${CLUSTER_NAME}" --region "${REGION}"

# 2. クラスタが消えるまで待機(describe-cluster が NotFound を返すまで)
while aws sagemaker describe-cluster --cluster-name "${CLUSTER_NAME}" --region "${REGION}" >/dev/null 2>&1; do
  echo "[delete-cluster] クラスタ削除中..."
  sleep 30
done
echo "[delete-cluster] クラスタ削除完了"
