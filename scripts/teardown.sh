#!/bin/bash
#
# HyperPod クラスタ + CDK スタックの完全削除
#
# 使い方:
#   ./scripts/teardown.sh
#
# 重要:
#   このスクリプトは課金停止のため必ず動作確認後に実行してください。
#   `delete-cluster` は非同期で実行されるため、完了を待たずに `cdk destroy` を
#   走らせると VPC 削除が ENI 残留で失敗します。本スクリプトは完了待ちを行います。
#

CLUSTER_NAME="aws-hyperpod-slurm-hello-world"
REGION="ap-northeast-1"

# 1. HyperPod クラスタ削除要求(非同期)
aws sagemaker delete-cluster --cluster-name "${CLUSTER_NAME}" --region "${REGION}"

# 2. クラスタが消えるまで待機(describe-cluster が NotFound を返すまで)
#    ml.g5.2xlarge の削除には数分かかる
while aws sagemaker describe-cluster --cluster-name "${CLUSTER_NAME}" --region "${REGION}" >/dev/null 2>&1; do
  echo "[teardown] クラスタ削除中..."
  sleep 30
done
echo "[teardown] クラスタ削除完了"

# 3. CDK スタック削除(VPC / NAT Gateway / IAM / S3)
#    NAT Gateway も含めて消えるので、ここから NAT 課金も止まる
cd "$(dirname "$0")/../cdk"
pnpm cdk destroy --all --force

# 4. 残留リソース確認(手動)
#    - aws ec2 describe-network-interfaces --filters Name=tag:project,Values=aws-hyperpod-slurm-hello-world --region ap-northeast-1
#    - aws cloudformation describe-stacks --region ap-northeast-1(スタックが消えていることを確認)
#    - AWS Cost Explorer で当日 / 翌日の SageMaker / EC2 料金が 0 円になることを確認
