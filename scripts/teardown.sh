#!/bin/bash
#
# 完全削除スクリプト(HyperPod クラスタ + DRA + FSx for Lustre + CDK スタック)
#
# 使い方:
#   ./scripts/teardown.sh
#
# 削除順序(これが肝):
#   1. HyperPod クラスタ削除(完全消失まで待機)
#   2. DRA 削除(数分-10 分。delete-fsx.sh が内包)
#   3. FSx for Lustre 削除(完全消失まで待機。delete-fsx.sh が内包)
#   4. CDK スタック削除(VPC / NAT / IAM / S3 / FsxSg)
#
# なぜこの順序か:
#   - クラスタが残ったまま FSx を消そうとすると、FSx 利用中で失敗
#   - DRA が残ったまま FSx を消そうとすると失敗(delete-fsx.sh が先に DRA を消す)
#   - FSx が残ったまま cdk destroy すると、FSx の ENI が VPC 内に残り
#     VPC 削除が失敗 → NAT が残って課金が止まらない
#   - 各削除 API は非同期。完了を待たずに次へ進むと残留トラブルになる
#
# 動作確認を繰り返したい(クラスタだけ消す)場合:
#   ./scripts/delete-cluster.sh を使ってください
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. HyperPod クラスタを削除(完了まで待機)
"${SCRIPT_DIR}/delete-cluster.sh"

# 2, 3. DRA → FSx for Lustre の順に削除(delete-fsx.sh が内包)
"${SCRIPT_DIR}/delete-fsx.sh"

# 4. CDK スタック削除(VPC / NAT / IAM / S3 / FsxSg)
#    NAT も含めて消えるので、ここから NAT 課金も止まる
cd "${SCRIPT_DIR}/../cdk"
pnpm cdk destroy --all --force

# 5. 残留リソース確認(手動)
#    - aws ec2 describe-network-interfaces --filters Name=tag:project,Values=aws-hyperpod-slurm-hello-world --region ap-northeast-1
#    - aws fsx describe-file-systems --region ap-northeast-1(FSx が無いことを確認)
#    - aws fsx describe-data-repository-associations --region ap-northeast-1(DRA が無いことを確認)
#    - aws cloudformation describe-stacks --region ap-northeast-1(スタックが消えていることを確認)
#    - AWS Cost Explorer で当日 / 翌日の SageMaker / EC2 / FSx 料金が 0 円になることを確認
