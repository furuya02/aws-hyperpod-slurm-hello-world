#!/bin/bash
#
# HyperPod クラスタ + CDK スタックの完全削除
#
# 使い方:
#   ./scripts/teardown.sh
#
# 注意:
#   クラスタだけ削除して VPC/NAT/IAM/S3 を残したい(動作確認を繰り返したい)場合は
#   ./scripts/delete-cluster.sh を使う。本スクリプトは CDK スタックごと全部消す。
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. HyperPod クラスタを削除(完了まで待機。ロジックは delete-cluster.sh に集約)
"${SCRIPT_DIR}/delete-cluster.sh"

# 2. CDK スタック削除(VPC / NAT Gateway / IAM / S3)
#    NAT Gateway も含めて消えるので、ここから NAT 課金も止まる
cd "${SCRIPT_DIR}/../cdk"
pnpm cdk destroy --all --force

# 3. 残留リソース確認(手動)
#    - aws ec2 describe-network-interfaces --filters Name=tag:project,Values=aws-hyperpod-slurm-hello-world --region ap-northeast-1
#    - aws cloudformation describe-stacks --region ap-northeast-1(スタックが消えていることを確認)
#    - AWS Cost Explorer で当日 / 翌日の SageMaker / EC2 料金が 0 円になることを確認
