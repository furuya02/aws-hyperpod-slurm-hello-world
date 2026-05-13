#!/bin/bash
#
# HyperPod クラスタ作成スクリプト
#
# 前提:
#   1. ./scripts/sync-lifecycle.sh で AWS Samples の lifecycle スクリプトを取り込み済み
#   2. cdk deploy 済み(VPC / IAM / S3 が存在)
#
# 使い方:
#   ./scripts/create.sh
#
# 注意:
#   このコマンドを実行した瞬間から ml.g5.2xlarge × 1 で約 8,000 円/日 の課金が始まります
#

CLUSTER_NAME="aws-hyperpod-slurm-hello-world"
REGION="ap-northeast-1"
STACK_NAME="AwsHyperpodSlurmHelloWorldStack"

# 1. CFn Outputs を jq で取り出す
OUTPUTS=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" --query 'Stacks[0].Outputs')
LIFECYCLE_BUCKET=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="LifecycleBucketName") | .OutputValue')
EXECUTION_ROLE_ARN=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="ExecutionRoleArn") | .OutputValue')
PRIVATE_SUBNET_ID=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="PrivateSubnetIds") | .OutputValue' | cut -d, -f1)
DEFAULT_SG_ID=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="DefaultSecurityGroupId") | .OutputValue')

# 2. lifecycle/ 配下を丸ごと S3 にアップロード(provisioning_parameters.json も含む)
#    HyperPod は SourceS3Uri に指定したプレフィックス配下のファイルをノードに同期する
aws s3 sync lifecycle/ "s3://${LIFECYCLE_BUCKET}/lifecycle/" --region "${REGION}" --exclude "*.override" --exclude "README.md" --exclude ".gitignore"

# 3. cluster-config.json のプレースホルダ <...> を実値に置換
sed \
  -e "s|<LIFECYCLE_BUCKET>|${LIFECYCLE_BUCKET}|g" \
  -e "s|<EXECUTION_ROLE_ARN>|${EXECUTION_ROLE_ARN}|g" \
  -e "s|<PRIVATE_SUBNET_ID>|${PRIVATE_SUBNET_ID}|g" \
  -e "s|<DEFAULT_SECURITY_GROUP_ID>|${DEFAULT_SG_ID}|g" \
  cluster-config.json > /tmp/cluster-config.json

# 4. create-cluster は --instance-groups に配列、--vpc-config にオブジェクトを別々に渡す必要があるため
#    cluster-config.json から jq で抜き出して 2 ファイルに分割
jq '.InstanceGroups' /tmp/cluster-config.json > /tmp/instance-groups.json
jq '.VpcConfig'      /tmp/cluster-config.json > /tmp/vpc-config.json

# 5. クラスタ作成(ここから課金開始)
aws sagemaker create-cluster \
  --cluster-name "${CLUSTER_NAME}" \
  --instance-groups file:///tmp/instance-groups.json \
  --vpc-config      file:///tmp/vpc-config.json \
  --region "${REGION}"
