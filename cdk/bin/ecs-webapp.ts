#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { EcsWebAppStack } from '../lib/ecs-webapp-stack';

const app = new cdk.App();

new EcsWebAppStack(app, 'milk-ecs-webapp-cdk', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  }
});
