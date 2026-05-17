#!/bin/bash
#
# FSx for Lustre + Data Repository Association (DRA) 作成スクリプト
#
# 前提:
#   - cdk deploy 済み(VPC / IAM / S3 / FsxSg + bucket Resource Policy が存在)
#
# 使い方:
#   ./scripts/create-fsx.sh
#
# 注意:
#   - FSx 作成完了まで 10-20 分かかります(AVAILABLE になるまで待機する)
#   - 続けて DRA(/fsx/jobs ↔ s3://lifecycle/jobs/) を作成し、AVAILABLE まで待機(数分-10 分)
#   - 作成完了時点から 約 1,200 円/日 の FSx 課金が始まります(NAT より高額)
#   - 削除は ./scripts/delete-fsx.sh で(DRA 先 → FSx の順、同じく数十分かかります)
#   - クラスタ作成は本スクリプト完了後に ./scripts/create.sh で行います
#

set -e

FSX_NAME="aws-hyperpod-slurm-hello-world-fsx"
DRA_FS_PATH="/jobs"
DRA_S3_PREFIX="jobs/"
REGION="ap-northeast-1"
STACK_NAME="AwsHyperpodSlurmHelloWorldStack"

# 1. CFn Outputs から subnet / FsxSg / lifecycle bucket を取得
OUTPUTS=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" --query 'Stacks[0].Outputs')
PRIVATE_SUBNET_ID=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="PrivateSubnetIds") | .OutputValue' | cut -d, -f1)
FSX_SG_ID=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="FsxSecurityGroupId") | .OutputValue')
LIFECYCLE_BUCKET=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="LifecycleBucketName") | .OutputValue')

# 2. 既存の同名 FSx がないか確認(重複作成防止)
EXISTING=$(aws fsx describe-file-systems --region "${REGION}" \
  --query "FileSystems[?Tags[?Key=='Name' && Value=='${FSX_NAME}']].FileSystemId" --output text)
if [ -n "${EXISTING}" ]; then
  echo "[create-fsx] 既存の FSx (${EXISTING}) が存在します。重複作成を中止"
  exit 1
fi

# 3. FSx for Lustre 作成
#    - PERSISTENT_2 SSD, 1.2 TiB, 125 MB/s/TiB (最小構成)
#    - Lustre 2.15 を明示指定(指定しないとデフォルトの 2.10 になり、AWS コンソールで
#      「2.15 へのアップグレード推奨」通知が出る。kit も 2.15 を採用)
FSX_ID=$(aws fsx create-file-system \
  --file-system-type LUSTRE \
  --file-system-type-version 2.15 \
  --storage-capacity 1200 \
  --storage-type SSD \
  --subnet-ids "${PRIVATE_SUBNET_ID}" \
  --security-group-ids "${FSX_SG_ID}" \
  --lustre-configuration "DeploymentType=PERSISTENT_2,PerUnitStorageThroughput=125" \
  --tags Key=Name,Value="${FSX_NAME}" \
  --region "${REGION}" \
  --query 'FileSystem.FileSystemId' --output text)

echo "[create-fsx] 作成要求送信: ${FSX_ID}"

# 4. FSx AVAILABLE になるまでポーリング(通常 10-20 分)
while true; do
  STATUS=$(aws fsx describe-file-systems --file-system-ids "${FSX_ID}" --region "${REGION}" \
    --query 'FileSystems[0].Lifecycle' --output text)
  echo "[create-fsx] FSx Status: ${STATUS}"
  case "${STATUS}" in
    AVAILABLE) break ;;
    FAILED|DELETING|DELETED) echo "[create-fsx] FSx FAILED"; exit 1 ;;
    *) sleep 30 ;;
  esac
done
echo "[create-fsx] FSx 完了: ${FSX_ID} (AVAILABLE)"

# 5. DRA(Data Repository Association)作成: /fsx/jobs ↔ s3://lifecycle/jobs/
#    - AutoImport: S3 側の変更を FSx に反映 (NEW/CHANGED/DELETED)
#    - AutoExport: FSx 側の変更を S3 に反映 (NEW/CHANGED/DELETED)
#    - BatchImportMetaDataOnCreate: 作成時に S3 既存オブジェクトのメタデータを import
DRA_ID=$(aws fsx create-data-repository-association \
  --file-system-id "${FSX_ID}" \
  --file-system-path "${DRA_FS_PATH}" \
  --data-repository-path "s3://${LIFECYCLE_BUCKET}/${DRA_S3_PREFIX}" \
  --batch-import-meta-data-on-create \
  --s3 'AutoImportPolicy={Events=["NEW","CHANGED","DELETED"]},AutoExportPolicy={Events=["NEW","CHANGED","DELETED"]}' \
  --region "${REGION}" \
  --query 'Association.AssociationId' --output text)

echo "[create-fsx] DRA 作成要求送信: ${DRA_ID}"

# 6. DRA AVAILABLE になるまでポーリング(通常 数分-10 分)
while true; do
  STATUS=$(aws fsx describe-data-repository-associations --association-ids "${DRA_ID}" --region "${REGION}" \
    --query 'Associations[0].Lifecycle' --output text)
  echo "[create-fsx] DRA Status: ${STATUS}"
  case "${STATUS}" in
    AVAILABLE) break ;;
    FAILED|DELETING|DELETED) echo "[create-fsx] DRA FAILED"; exit 1 ;;
    *) sleep 30 ;;
  esac
done
echo "[create-fsx] DRA 完了: ${DRA_ID} (AVAILABLE)"
echo "[create-fsx] 次は ./scripts/create.sh でクラスタを作成してください"
