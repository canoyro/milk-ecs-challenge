#!/usr/bin/env bash
set -euo pipefail

account_id="${AWS_ACCOUNT_ID:-581145854871}"
region="${AWS_REGION:-ap-southeast-2}"
repo="${GITHUB_REPOSITORY:-canoyro/milk-ecs-challenge}"
role_name="${CDK_GITHUB_ROLE_NAME:-github-actions-milk-ecs-cdk}"
stack_name="${CDK_STACK_NAME:-milk-ecs-webapp-cdk}"
static_bucket="${CDK_STATIC_ASSETS_BUCKET:-milk-ecs-webapp-cdk-static-assets-${account_id}-${region}}"
repository_name="${CDK_ECR_REPOSITORY:-milk-ecs-webapp-cdk-webapp}"
oidc_provider_arn="arn:aws:iam::${account_id}:oidc-provider/token.actions.githubusercontent.com"

trust_policy="$(mktemp)"
permissions_policy="$(mktemp)"
bootstrap_policy="$(mktemp)"
trap 'rm -f "$trust_policy" "$permissions_policy" "$bootstrap_policy"' EXIT

file_uri() {
  if command -v cygpath >/dev/null 2>&1; then
    printf 'file://%s' "$(cygpath -w "$1")"
  else
    printf 'file://%s' "$1"
  fi
}

cat > "$trust_policy" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${oidc_provider_arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:${repo}:ref:refs/heads/main",
            "repo:${repo}:ref:refs/tags/v*",
            "repo:${repo}:pull_request"
          ]
        }
      }
    }
  ]
}
JSON

cat > "$permissions_policy" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AssumeCdkBootstrapRoles",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": [
        "arn:aws:iam::${account_id}:role/cdk-hnb659fds-deploy-role-${account_id}-${region}",
        "arn:aws:iam::${account_id}:role/cdk-hnb659fds-file-publishing-role-${account_id}-${region}",
        "arn:aws:iam::${account_id}:role/cdk-hnb659fds-image-publishing-role-${account_id}-${region}",
        "arn:aws:iam::${account_id}:role/cdk-hnb659fds-lookup-role-${account_id}-${region}"
      ]
    },
    {
      "Sid": "ReadCdkToolkitAndAppStacks",
      "Effect": "Allow",
      "Action": [
        "cloudformation:DescribeStacks",
        "cloudformation:DescribeStackEvents",
        "cloudformation:DescribeStackResources",
        "cloudformation:DescribeChangeSet",
        "cloudformation:GetTemplate"
      ],
      "Resource": [
        "arn:aws:cloudformation:${region}:${account_id}:stack/CDKToolkit/*",
        "arn:aws:cloudformation:${region}:${account_id}:stack/${stack_name}/*"
      ]
    },
    {
      "Sid": "ReadCdkBootstrapVersion",
      "Effect": "Allow",
      "Action": "ssm:GetParameter",
      "Resource": "arn:aws:ssm:${region}:${account_id}:parameter/cdk-bootstrap/hnb659fds/version"
    },
    {
      "Sid": "ReadCdkStaticAssetsBucketLocation",
      "Effect": "Allow",
      "Action": "s3:GetBucketLocation",
      "Resource": "arn:aws:s3:::${static_bucket}"
    },
    {
      "Sid": "ListCdkStaticAssets",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${static_bucket}",
      "Condition": {
        "StringLike": {
          "s3:prefix": [
            "assets",
            "assets/*"
          ]
        }
      }
    },
    {
      "Sid": "ManageCdkStaticAssetObjects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::${static_bucket}/assets/*"
    },
    {
      "Sid": "AuthenticateToEcr",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "PushCdkWebAppImages",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:BatchGetImage",
        "ecr:DescribeRepositories",
        "ecr:DescribeImages"
      ],
      "Resource": "arn:aws:ecr:${region}:${account_id}:repository/${repository_name}"
    }
  ]
}
JSON

cat > "$bootstrap_policy" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ManageCdkToolkitChangeSets",
      "Effect": "Allow",
      "Action": [
        "cloudformation:CreateChangeSet",
        "cloudformation:ExecuteChangeSet",
        "cloudformation:DeleteChangeSet",
        "cloudformation:DescribeChangeSet",
        "cloudformation:DescribeStacks",
        "cloudformation:DescribeEvents",
        "cloudformation:DescribeStackEvents",
        "cloudformation:DescribeStackResources",
        "cloudformation:GetTemplate",
        "cloudformation:CreateStack",
        "cloudformation:UpdateStack"
      ],
      "Resource": "arn:aws:cloudformation:${region}:${account_id}:stack/CDKToolkit/*"
    }
  ]
}
JSON

if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
  aws iam update-assume-role-policy \
    --role-name "$role_name" \
    --policy-document "$(file_uri "$trust_policy")"
else
  aws iam create-role \
    --role-name "$role_name" \
    --assume-role-policy-document "$(file_uri "$trust_policy")"
fi

aws iam put-role-policy \
  --role-name "$role_name" \
  --policy-name AllowCdkGitHubDeployments \
  --policy-document "$(file_uri "$permissions_policy")"

aws iam put-role-policy \
  --role-name "$role_name" \
  --policy-name AllowCdkGitHubBootstrap \
  --policy-document "$(file_uri "$bootstrap_policy")"

echo "Created or updated arn:aws:iam::${account_id}:role/${role_name}"
echo "Set GitHub secret AWS_CDK_ROLE_TO_ASSUME to arn:aws:iam::${account_id}:role/${role_name}"
