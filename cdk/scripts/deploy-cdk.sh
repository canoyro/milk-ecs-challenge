#!/usr/bin/env bash
set -euo pipefail

: "${CDK_VPC_ID:?CDK_VPC_ID is required}"
: "${CDK_PUBLIC_SUBNET_IDS:?CDK_PUBLIC_SUBNET_IDS is required}"
: "${CDK_SECURITY_GROUP_ID:?CDK_SECURITY_GROUP_ID is required}"

stack_name="${CDK_STACK_NAME:-milk-ecs-webapp-cdk}"
container_image="${CONTAINER_IMAGE:-${CDK_CONTAINER_IMAGE:-nginx:latest}}"
instance_type="${CDK_INSTANCE_TYPE:-t3.micro}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."

npx cdk deploy "$stack_name" \
  --require-approval never \
  -c vpcId="$CDK_VPC_ID" \
  -c publicSubnetIds="$CDK_PUBLIC_SUBNET_IDS" \
  -c securityGroupId="$CDK_SECURITY_GROUP_ID" \
  -c containerImage="$container_image" \
  -c instanceType="$instance_type"
