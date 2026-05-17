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

    // S3 Bucket: lifecycle スクリプト配置用 + FSx DRA の S3 連携先(cdk destroy で確実に削除)
    //   - lifecycle/ プレフィックス: HyperPod ノードへの sync 用(従来通り)
    //   - jobs/      プレフィックス: FSx for Lustre の DRA で /fsx/jobs → s3://.../jobs/ に自動 export
    const lifecycleBucket: s3.Bucket = new s3.Bucket(this, "LifecycleBucket", {
      bucketName: `${PROJECT_NAME}-${bucketSuffix}-lifecycle`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });
    // FSx サービスから本バケットへのアクセスを許可する Resource Policy
    // (DRA(Data Repository Association)を作成すると FSx サービスが S3 オブジェクトを直接読み書きするため必要)
    lifecycleBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal("fsx.amazonaws.com")],
        actions: [
          "s3:AbortMultipartUpload",
          "s3:DeleteObject",
          "s3:Get*",
          "s3:List*",
          "s3:PutBucketNotification",
          "s3:PutObject",
        ],
        resources: [lifecycleBucket.bucketArn, `${lifecycleBucket.bucketArn}/*`],
      }),
    );

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

    // FSx for Lustre 用 SG (FSx 本体は scripts/create-fsx.sh で別建てに作成)
    //   - FSx を CDK の外に出している理由:
    //       「VPC+NAT (cdk deploy) → FSx (create-fsx.sh) → クラスタ (create.sh)」と
    //       課金フェーズを 3 段で観察できるようにするため(教育的観点)
    //   - SG だけは CDK で固定し、create-fsx.sh から参照する(SG は無料)
    //   - Lustre プロトコル: ポート 988, 1021-1023
    const fsxSg: ec2.SecurityGroup = new ec2.SecurityGroup(this, "FsxSg", {
      vpc,
      securityGroupName: `${PROJECT_NAME}-fsx-sg`,
      description: "Security group for FSx for Lustre (Lustre protocol 988, 1021-1023)",
      allowAllOutbound: true,
    });
    // HyperPod ノードは VPC default SG に所属するため、default SG からの ingress を許可
    const defaultSg: ec2.ISecurityGroup = ec2.SecurityGroup.fromSecurityGroupId(
      this,
      "DefaultSgRef",
      vpc.vpcDefaultSecurityGroup,
    );
    fsxSg.addIngressRule(defaultSg, ec2.Port.tcp(988), "Lustre from HyperPod nodes");
    fsxSg.addIngressRule(defaultSg, ec2.Port.tcpRange(1021, 1023), "Lustre from HyperPod nodes");
    // FSx 自己参照(OST 間通信)
    fsxSg.addIngressRule(fsxSg, ec2.Port.tcp(988), "Lustre self");
    fsxSg.addIngressRule(fsxSg, ec2.Port.tcpRange(1021, 1023), "Lustre self");

    // Outputs: scripts/create.sh / create-fsx.sh が CFn Outputs から取り出して使う
    new cdk.CfnOutput(this, "VpcId", { value: vpc.vpcId });
    new cdk.CfnOutput(this, "PrivateSubnetIds", {
      value: vpc.privateSubnets.map((s: ec2.ISubnet) => s.subnetId).join(","),
    });
    new cdk.CfnOutput(this, "DefaultSecurityGroupId", { value: vpc.vpcDefaultSecurityGroup });
    new cdk.CfnOutput(this, "LifecycleBucketName", { value: lifecycleBucket.bucketName });
    new cdk.CfnOutput(this, "ExecutionRoleArn", { value: executionRole.roleArn });
    new cdk.CfnOutput(this, "FsxSecurityGroupId", { value: fsxSg.securityGroupId });
  }
}
