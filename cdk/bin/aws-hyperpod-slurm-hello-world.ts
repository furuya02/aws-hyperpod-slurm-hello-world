#!/usr/bin/env node
import "source-map-support/register";
import * as cdk from "aws-cdk-lib";
import { AwsHyperpodSlurmHelloWorldStack } from "../lib/aws-hyperpod-slurm-hello-world-stack";

const app: cdk.App = new cdk.App();

const bucketSuffix: string | undefined = app.node.tryGetContext("bucket_suffix");

new AwsHyperpodSlurmHelloWorldStack(app, "AwsHyperpodSlurmHelloWorldStack", {
  bucketSuffix,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION ?? "ap-northeast-1",
  },
});
