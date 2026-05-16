import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as iam from "aws-cdk-lib/aws-iam";
import * as s3 from "aws-cdk-lib/aws-s3";

// プロジェクト名(リソース名の prefix)
const PROJECT_NAME: string = "aws-hyperpod-slurm-hello-world";

export interface AwsHyperpodSlurmHelloWorldStackProps extends cdk.StackProps {
  // S3 バケットの suffix(未指定時はアカウント ID)
  bucketSuffix?: string;
}

export class AwsHyperpodSlurmHelloWorldStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: AwsHyperpodSlurmHelloWorldStackProps) {
    super(scope, id, props);

    const bucketSuffix: string = props.bucketSuffix ?? cdk.Stack.of(this).account;

    // VPC: パブリック 1 / プライベート 1、NAT Gateway 1 つの最小構成
    const vpc: ec2.Vpc = new ec2.Vpc(this, "Vpc", {
      vpcName: `${PROJECT_NAME}-vpc`,
      maxAzs: 1,
      natGateways: 1,
    });

    // S3 Bucket: lifecycle スクリプト配置用(cdk destroy で確実に削除)
    const lifecycleBucket: s3.Bucket = new s3.Bucket(this, "LifecycleBucket", {
      bucketName: `${PROJECT_NAME}-${bucketSuffix}-lifecycle`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // IAM Role: HyperPod 実行ロール(sample-physical-ai-scaffolding-kit の ExecutionRole 準拠)
    //   - 信頼関係: sagemaker.amazonaws.com
    //   - マネージドポリシー: AmazonSageMakerClusterInstanceRolePolicy
    //     (CloudWatch Logs / メトリクス / SSM messages / S3(sagemaker-*) を含む。
    //      SSM 接続は本ポリシーの ssmmessages:* で足りるため AmazonSSMManagedInstanceCore は不要)
    //   - インラインポリシー: ENI/VPC 操作・クラスタ管理 API・ECR(kit と同一)
    //   - lifecycle バケットへの R/W は grantReadWrite で付与(kit と同じやり方)
    const executionRole: iam.Role = new iam.Role(this, "ExecutionRole", {
      roleName: `${PROJECT_NAME}-execution-role`,
      assumedBy: new iam.ServicePrincipal("sagemaker.amazonaws.com"),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonSageMakerClusterInstanceRolePolicy"),
      ],
    });
    lifecycleBucket.grantReadWrite(executionRole);

    // AllowInterface: HyperPod が VPC 内に ENI を作成し、サブネット等を検証するための EC2 権限
    //   (これが無いと create-cluster が "Unable to retrieve subnets" で失敗する)
    executionRole.addToPolicy(
      new iam.PolicyStatement({
        actions: [
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeVpcs",
          "ec2:DescribeDhcpOptions",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:CreateNetworkInterface",
          "ec2:CreateNetworkInterfacePermission",
          "ec2:CreateTags",
          "ec2:DetachNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DeleteNetworkInterfacePermission",
        ],
        resources: ["*"],
      }),
    );

    // AllowClusterUpdate: ノード上の lifecycle スクリプト等がクラスタ情報を参照するための権限
    executionRole.addToPolicy(
      new iam.PolicyStatement({
        actions: [
          "sagemaker:DeleteCluster",
          "sagemaker:DescribeCluster",
          "sagemaker:DescribeClusterNode",
          "sagemaker:ListClusterNodes",
          "sagemaker:UpdateCluster",
          "sagemaker:UpdateClusterSoftware",
          "sagemaker:BatchDeleteClusterNodes",
          "sagemaker:ListClusters",
          "cloudformation:DescribeStacks",
        ],
        resources: ["*"],
      }),
    );

    // AllowEcrRepositoryPolicy: kit 準拠(本記事は Docker 無効のため実質未使用だが kit に合わせて付与)
    executionRole.addToPolicy(
      new iam.PolicyStatement({
        actions: [
          "ecr:CreateRepository",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:GetAuthorizationToken",
        ],
        resources: ["*"],
      }),
    );

    // Outputs: scripts/create.sh が CFn Outputs から取り出して cluster-config.json に流し込む
    new cdk.CfnOutput(this, "VpcId", { value: vpc.vpcId });
    new cdk.CfnOutput(this, "PrivateSubnetIds", {
      value: vpc.privateSubnets.map((s: ec2.ISubnet) => s.subnetId).join(","),
    });
    new cdk.CfnOutput(this, "DefaultSecurityGroupId", { value: vpc.vpcDefaultSecurityGroup });
    new cdk.CfnOutput(this, "LifecycleBucketName", { value: lifecycleBucket.bucketName });
    new cdk.CfnOutput(this, "ExecutionRoleArn", { value: executionRole.roleArn });
  }
}
