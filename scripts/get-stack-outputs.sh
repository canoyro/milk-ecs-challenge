#!/usr/bin/env bash
set -euo pipefail

: "${STACK_NAME:?STACK_NAME is required}"

stack_outputs=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs" \
  --output json)

repository_uri=$(echo "$stack_outputs" | jq -r '.[] | select(.OutputKey == "ECRRepositoryUri") | .OutputValue')
static_assets_bucket=$(echo "$stack_outputs" | jq -r '.[] | select(.OutputKey == "StaticAssetsBucketName") | .OutputValue')

if [ -z "$repository_uri" ] || [ "$repository_uri" = "null" ]; then
  echo "ECRRepositoryUri stack output was not found." >&2
  exit 1
fi

if [ -z "$static_assets_bucket" ] || [ "$static_assets_bucket" = "null" ]; then
  echo "StaticAssetsBucketName stack output was not found." >&2
  exit 1
fi

{
  echo "repository_uri=$repository_uri"
  echo "static_assets_bucket=$static_assets_bucket"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"
