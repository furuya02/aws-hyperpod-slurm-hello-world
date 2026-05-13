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

    // IAM Role: HyperPod 実行ロール
    //   - 信頼関係: sagemaker.amazonaws.com
    //   - 権限: SSM Managed Instance Core + S3 R/W(lifecycle bucket)
    const executionRole: iam.Role = new iam.Role(this, "ExecutionRole", {
      roleName: `${PROJECT_NAME}-execution-role`,
      assumedBy: new iam.ServicePrincipal("sagemaker.amazonaws.com"),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMManagedInstanceCore"),
      ],
    });
    lifecycleBucket.grantReadWrite(executionRole);

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
