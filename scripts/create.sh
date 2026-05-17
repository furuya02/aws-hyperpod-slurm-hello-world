#!/bin/bash
#
# HyperPod クラスタ作成スクリプト
#
# 前提:
#   1. ./scripts/sync-lifecycle.sh で AWS 公式 (awslabs/awsome-distributed-ai)
#      の lifecycle スクリプトを取り込み済み
#   2. cdk deploy 済み(VPC / IAM / S3 が存在)
#   3. ./scripts/create-fsx.sh 済み(FSx for Lustre が AVAILABLE)
#
# 使い方:
#   ./scripts/create.sh
#
# 注意:
#   このコマンドを実行した瞬間からクラスタ分 約 8,800 円/日 が上乗せされ、
#   既存の NAT + FSx 課金と合わせて 合計 約 10,200 円/日 になります。
#

set -e

CLUSTER_NAME="aws-hyperpod-slurm-hello-world"
FSX_NAME="aws-hyperpod-slurm-hello-world-fsx"
REGION="ap-northeast-1"
STACK_NAME="AwsHyperpodSlurmHelloWorldStack"

# 1. CFn Outputs を jq で取り出す
OUTPUTS=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" --query 'Stacks[0].Outputs')
LIFECYCLE_BUCKET=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="LifecycleBucketName") | .OutputValue')
EXECUTION_ROLE_ARN=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="ExecutionRoleArn") | .OutputValue')
PRIVATE_SUBNET_ID=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="PrivateSubnetIds") | .OutputValue' | cut -d, -f1)
DEFAULT_SG_ID=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="DefaultSecurityGroupId") | .OutputValue')

# 2. FSx for Lustre の DNSName / MountName を Name タグから引く
#    (FSx は CDK 外で別建てに作っているため、CFn Outputs には含まれない)
FSX_INFO=$(aws fsx describe-file-systems --region "${REGION}" \
  --query "FileSystems[?Tags[?Key=='Name' && Value=='${FSX_NAME}']]|[0]")
FSX_DNS_NAME=$(echo "${FSX_INFO}" | jq -r '.DNSName')
FSX_MOUNT_NAME=$(echo "${FSX_INFO}" | jq -r '.LustreConfiguration.MountName')

if [ "${FSX_DNS_NAME}" == "null" ] || [ -z "${FSX_DNS_NAME}" ]; then
  echo "[create.sh] FSx for Lustre が見つかりません。先に ./scripts/create-fsx.sh を実行してください"
  exit 1
fi

# 3. lifecycle/provisioning_parameters.json の <FSX_*> プレースホルダを実値に置換
#    (lifecycle_script.py が起動時に mount_fsx.sh を呼び /fsx へマウントする)
sed \
  -e "s|<FSX_DNS_NAME>|${FSX_DNS_NAME}|g" \
  -e "s|<FSX_MOUNT_NAME>|${FSX_MOUNT_NAME}|g" \
  lifecycle/provisioning_parameters.json > /tmp/provisioning_parameters.json

# 4. lifecycle/ 配下を丸ごと S3 にアップロード
#    HyperPod は SourceS3Uri に指定したプレフィックス配下のファイルをノードに同期する
aws s3 sync lifecycle/ "s3://${LIFECYCLE_BUCKET}/lifecycle/" --region "${REGION}" --exclude "*.override" --exclude "README.md" --exclude ".gitignore"

# 5. provisioning_parameters.json は置換版で上書き(S3 上の原本を実値版に差し替え)
aws s3 cp /tmp/provisioning_parameters.json "s3://${LIFECYCLE_BUCKET}/lifecycle/provisioning_parameters.json" --region "${REGION}"

# 6. cluster-config.json のプレースホルダ <...> を実値に置換
sed \
  -e "s|<LIFECYCLE_BUCKET>|${LIFECYCLE_BUCKET}|g" \
  -e "s|<EXECUTION_ROLE_ARN>|${EXECUTION_ROLE_ARN}|g" \
  -e "s|<PRIVATE_SUBNET_ID>|${PRIVATE_SUBNET_ID}|g" \
  -e "s|<DEFAULT_SECURITY_GROUP_ID>|${DEFAULT_SG_ID}|g" \
  cluster-config.json > /tmp/cluster-config.json

# 7. create-cluster は --instance-groups に配列、--vpc-config にオブジェクトを別々に渡す必要があるため
#    cluster-config.json から jq で抜き出して 2 ファイルに分割
jq '.InstanceGroups' /tmp/cluster-config.json > /tmp/instance-groups.json
jq '.VpcConfig'      /tmp/cluster-config.json > /tmp/vpc-config.json

# 8. クラスタ作成(ここからクラスタ分 約 8,800 円/日 が上乗せ)
aws sagemaker create-cluster \
  --cluster-name "${CLUSTER_NAME}" \
  --instance-groups file:///tmp/instance-groups.json \
  --vpc-config      file:///tmp/vpc-config.json \
  --region "${REGION}"
