# ECS EC2 Web App Stack

This project deploys the core MILK Books DevOps challenge stack with AWS CloudFormation. It creates an ECS cluster using the EC2 launch type, runs a simple containerized web application, spreads two service tasks across two ECS container instances, and exposes the service through an Application Load Balancer.

ECR, S3, and GitHub Actions are included for image publishing, static asset serving, and rollout automation. CloudFront is intentionally deferred until the ECS service is working end to end.

For a reviewer-focused implementation brief, see `docs/project-summary.md`.

## Architecture

- Existing VPC, public subnets, and security group are supplied through `parameters.json`.
- The public subnets must be in different Availability Zones because the Application Load Balancer cannot attach to multiple subnets in the same Availability Zone.
- Stack-created resources use the CloudFormation stack name as their name prefix, for example `milk-ecs-webapp-cluster`, `milk-ecs-webapp-asg`, and `milk-ecs-webapp-alb`.
- An ECR repository stores the custom web app image.
- An S3 bucket serves static assets such as CSS and the demo logo under the `assets/` prefix.
- An Auto Scaling Group launches two ECS optimized Amazon Linux 2 EC2 instances.
- The ECS agent registers both instances into the ECS cluster during boot.
- An ECS capacity provider connects the Auto Scaling Group to the cluster.
- An ECS service runs two copies of the `web` task and uses placement strategies to spread tasks across Availability Zones and EC2 instances where capacity allows.
- An internet-facing Application Load Balancer forwards HTTP traffic to the ECS tasks.
- Container logs are written to CloudWatch Logs.
- GitHub Actions can build the app image, push it to ECR, and redeploy the ECS service with a Git SHA image tag.

## Prerequisites

- AWS CLI v2 installed and configured.
- Docker installed and running for local app builds.
- An AWS identity with permission to create CloudFormation, ECR, S3, ECS, EC2, Auto Scaling, IAM, Elastic Load Balancing, CloudWatch Logs, and SSM parameter resources.
- Existing VPC, public subnets, and security group.
- The security group must allow inbound HTTP traffic to the load balancer and allow the load balancer to reach port 80 on the ECS instances.
- If the same security group is used for both the ALB and ECS instances, add an inbound HTTP rule with the security group itself as the source.

## Configure Parameters

Update `parameters.json` with values for your AWS account:

- `VpcId`: existing VPC ID.
- `PubSubnets`: comma-separated public subnet IDs. Use one subnet per Availability Zone.
- `SecurityGroup`: existing security group ID.
- `ContainerImage`: image to deploy, defaulting to `nginx:latest`.
- `InstanceType`: EC2 instance size for ECS container instances. `t3.micro` is the default because it is Free Tier eligible in this region/account and compatible with the ECS optimized Amazon Linux 2 AMI.

`PrivSubnets` is not used by the core stack. It can be added later if the architecture moves ECS instances into private subnets.

Check the Availability Zones for your subnet IDs:

```bash
aws ec2 describe-subnets \
  --subnet-ids subnet-0f3b2f2ec01dcdc0e subnet-070016a5fa27ca914 \
  --query "Subnets[].{SubnetId:SubnetId,AvailabilityZone:AvailabilityZone,MapPublicIpOnLaunch:MapPublicIpOnLaunch}" \
  --output table
```

If both `PubSubnets` are in the same Availability Zone, replace one of them in `parameters.json` with a public subnet from a different Availability Zone in the same VPC.

## Build The Web App

The `app/` directory contains a small Nginx-based web app. At startup, the container reads ECS task metadata and renders `index.html` with task, container instance, Availability Zone, and hostname values. Build and test it locally first:

```bash
docker build -t milk-ecs-webapp:v1 ./app
docker run --rm -p 8080:80 milk-ecs-webapp:v1
```

In another terminal, verify the local container:

```bash
curl http://localhost:8080
```

Deploy the stack once to create the ECR repository, then get the repository URI:

```bash
aws cloudformation deploy \
  --stack-name milk-ecs-webapp \
  --template-file ecs-webapp.yaml \
  --parameter-overrides file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM

repository_uri=$(aws cloudformation describe-stacks \
  --stack-name milk-ecs-webapp \
  --query "Stacks[0].Outputs[?OutputKey=='ECRRepositoryUri'].OutputValue" \
  --output text)
```

Log in to ECR, tag the image, and push it:

```bash
aws ecr get-login-password | docker login --username AWS --password-stdin "${repository_uri%/*}"
docker tag milk-ecs-webapp:v1 "$repository_uri:v1"
docker push "$repository_uri:v1"
```

Update `ContainerImage` in `parameters.json` to the pushed ECR image URI, for example `123456789012.dkr.ecr.ap-southeast-2.amazonaws.com/milk-ecs-webapp-webapp:v1`.

## Upload Static Assets To S3

The stack creates an S3 bucket for static assets and exposes its public asset base URL to the ECS task as `STATIC_ASSET_BASE_URL`. The app uses that URL for `theme.css` and `milk-mark.svg`.

Upload the local assets after the stack has created the bucket:

```bash
static_bucket=$(aws cloudformation describe-stacks \
  --stack-name milk-ecs-webapp \
  --query "Stacks[0].Outputs[?OutputKey=='StaticAssetsBucketName'].OutputValue" \
  --output text)

aws s3 sync ./app/assets "s3://$static_bucket/assets" --delete
```

Verify one public static asset:

```bash
static_asset_base_url=$(aws cloudformation describe-stacks \
  --stack-name milk-ecs-webapp \
  --query "Stacks[0].Outputs[?OutputKey=='StaticAssetBaseURL'].OutputValue" \
  --output text)

curl "$static_asset_base_url/theme.css"
```

The S3 bucket policy allows public read access only for objects under `assets/*`. This keeps the demo simple and low-cost without CloudFront. In production, CloudFront with Origin Access Control would be preferred.

## Deploy

```bash
aws cloudformation deploy \
  --stack-name milk-ecs-webapp \
  --template-file ecs-webapp.yaml \
  --parameter-overrides file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM
```

## CDK TypeScript Version

The `cdk/` directory contains a TypeScript CDK implementation of the same ECS EC2 web app stack. It is included as a bonus version while keeping the original CloudFormation template available for direct comparison.

Install dependencies and synthesize the CDK stack:

```bash
cd cdk
npm install
npm run build
npx cdk synth \
  -c vpcId=vpc-04571bb185086fe7f \
  -c publicSubnetIds=subnet-0f3b2f2ec01dcdc0e,subnet-070016a5fa27ca914 \
  -c securityGroupId=sg-00778e9ef90895626 \
  -c containerImage=nginx:latest \
  -c instanceType=t3.micro
```

Deploy the CDK stack:

```bash
npx cdk bootstrap
npx cdk deploy \
  -c vpcId=vpc-04571bb185086fe7f \
  -c publicSubnetIds=subnet-0f3b2f2ec01dcdc0e,subnet-070016a5fa27ca914 \
  -c securityGroupId=sg-00778e9ef90895626 \
  -c containerImage=nginx:latest \
  -c instanceType=t3.micro
```

The CDK stack creates the same core resources as `ecs-webapp.yaml`: ECR, the S3 static assets bucket, ECS cluster, EC2 Auto Scaling capacity provider, bridge-mode task definition, ECS service, Application Load Balancer, target group, listener, CloudWatch Logs, and IAM roles.

Get the application URL:

```bash
aws cloudformation describe-stacks \
  --stack-name milk-ecs-webapp-cdk \
  --query "Stacks[0].Outputs[?OutputKey=='ApplicationURL'].OutputValue" \
  --output text
```

## Verify

Confirm two ECS container instances are registered:

```bash
cluster=$(aws cloudformation describe-stacks --stack-name milk-ecs-webapp --query "Stacks[0].Outputs[?OutputKey=='ECSClusterName'].OutputValue" --output text)
aws ecs list-container-instances --cluster "$cluster"
```

Confirm the ECS service has two running tasks:

```bash
service=$(aws cloudformation describe-stacks --stack-name milk-ecs-webapp --query "Stacks[0].Outputs[?OutputKey=='ECSServiceName'].OutputValue" --output text)
aws ecs describe-services --cluster "$cluster" --services "$service" --query "services[0].runningCount"
```

Confirm the load balancer serves the app:

```bash
url=$(aws cloudformation describe-stacks --stack-name milk-ecs-webapp --query "Stacks[0].Outputs[?OutputKey=='ApplicationURL'].OutputValue" --output text)
curl "$url"
```

Confirm that the ALB is balancing across tasks by sending repeated requests and comparing the rendered `Task ID`, `Container instance`, or `Hostname` values:

```bash
for i in {1..10}; do
  curl -s "$url" | grep -E "Task ID|Container instance|Hostname"
  echo
done
```

## Roll Out A New App Version

The preferred release path is GitHub Actions. Change files under `app/`, open a pull request, and merge it into `main`. The app workflow builds the image, tags it with the Git commit SHA, pushes it to ECR, and redeploys the ECS service with that immutable image URI.

For a manual fallback, build and push an explicit image tag:

```bash
repository_uri=$(aws cloudformation describe-stacks \
  --stack-name milk-ecs-webapp \
  --query "Stacks[0].Outputs[?OutputKey=='ECRRepositoryUri'].OutputValue" \
  --output text)

image_tag=$(git rev-parse --short=12 HEAD)

docker build \
  --build-arg APP_VERSION="$image_tag" \
  --build-arg IMAGE_TAG="$image_tag" \
  -t "$repository_uri:$image_tag" \
  ./app

docker push "$repository_uri:$image_tag"
```

Redeploy CloudFormation with the new image:

```bash
parameter_overrides=$(jq -r '.[] | select(.ParameterKey != "ContainerImage") | "\(.ParameterKey)=\(.ParameterValue)"' parameters.json)

aws cloudformation deploy \
  --stack-name milk-ecs-webapp \
  --template-file ecs-webapp.yaml \
  --parameter-overrides $parameter_overrides ContainerImage="$repository_uri:$image_tag" \
  --capabilities CAPABILITY_NAMED_IAM
```

CloudFormation registers a new task definition revision and ECS rolls the service to the new image. The app displays the image tag so the running version is visible in the browser.

## GitHub Actions Deployment

GitHub Actions is split into two workflows so infrastructure and app releases can move independently.

The workflow at `.github/workflows/deploy-infra.yml` runs when infrastructure files change:

- `ecs-webapp.yaml`
- `parameters.json`
- `.github/workflows/deploy-infra.yml`

It deploys or updates the CloudFormation stack only. It does not build or push an app image.

The workflow at `.github/workflows/deploy-app.yml` runs when app files change:

- `app/**`
- `scripts/**`
- `.github/workflows/deploy-app.yml`

It reads the ECR repository URI from stack outputs, syncs `app/assets` to S3, builds `app/`, pushes an immutable image tag using the first 12 characters of the Git commit SHA, then redeploys CloudFormation with `ContainerImage` set to that exact ECR image URI.

Do not use `latest` for ECS deployments. The deployed image should be an immutable Git SHA tag so every running task maps back to a specific commit. For release tags such as `v1.0.0`, the app workflow also pushes a semantic image tag such as `1.0.0`, but still deploys the Git SHA tag.

Configure these repository settings before running the workflow:

- Secret `AWS_ROLE_TO_ASSUME`: IAM role ARN that GitHub Actions can assume through OIDC.
- Variable `AWS_REGION`: AWS region, defaulting to `ap-southeast-2` if omitted.
- Variable `STACK_NAME`: CloudFormation stack name, defaulting to `milk-ecs-webapp` if omitted.

The GitHub OIDC role needs permissions for CloudFormation deploys, ECR image push, and the AWS resources created by this template.

If you use a least-privilege custom IAM policy for the GitHub Actions role, include `cloudformation:GetTemplateSummary`, `ssm:GetParameters`, and S3 permissions to sync objects into `arn:aws:s3:::milk-ecs-webapp-static-assets-581145854871-ap-southeast-2/assets/*`. The AWS CLI `cloudformation deploy` command calls `cloudformation:GetTemplateSummary`, and CloudFormation calls `ssm:GetParameters` to resolve the public ECS optimized AMI parameter.

## Developer Workflow

Use pull requests into `main` as the deployment boundary. Feature branches are safe to push because the deployment workflows only run for `main` or release tags.

For application changes, edit files under `app/`, test the image locally, then open a pull request:

```bash
docker build -t milk-ecs-webapp:dev ./app
docker run --rm -p 8080:80 milk-ecs-webapp:dev
curl http://localhost:8080
```

After the PR is merged to `main`, `.github/workflows/deploy-app.yml` runs. It builds the app image, pushes an immutable Git SHA tag to ECR, and updates the ECS service by redeploying CloudFormation with that exact image URI.

For infrastructure changes, edit `ecs-webapp.yaml`, `parameters.json`, or `.github/workflows/deploy-infra.yml`, then validate locally:

```bash
aws cloudformation validate-template --template-body file://ecs-webapp.yaml
```

After the PR is merged to `main`, `.github/workflows/deploy-infra.yml` runs. It deploys CloudFormation only and does not build or push an app image.

For a named release, create and push a Git tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The app workflow deploys the immutable Git SHA tag and also pushes a semantic ECR tag without using it as the deployed value. This keeps rollbacks precise while still giving humans a readable release tag.

To roll back, redeploy a previous immutable image tag:

```bash
repository_uri=$(aws cloudformation describe-stacks \
  --stack-name milk-ecs-webapp \
  --query "Stacks[0].Outputs[?OutputKey=='ECRRepositoryUri'].OutputValue" \
  --output text)

parameter_overrides=$(jq -r '.[] | select(.ParameterKey != "ContainerImage") | "\(.ParameterKey)=\(.ParameterValue)"' parameters.json)

aws cloudformation deploy \
  --stack-name milk-ecs-webapp \
  --template-file ecs-webapp.yaml \
  --parameter-overrides $parameter_overrides ContainerImage="$repository_uri:<previous-sha>" \
  --capabilities CAPABILITY_NAMED_IAM
```

## Validate

```bash
aws cloudformation validate-template --template-body file://ecs-webapp.yaml
```

## Clean Up

```bash
aws cloudformation delete-stack --stack-name milk-ecs-webapp
```

If static assets have been uploaded, empty the S3 bucket before deleting the stack:

```bash
static_bucket=$(aws cloudformation describe-stacks \
  --stack-name milk-ecs-webapp \
  --query "Stacks[0].Outputs[?OutputKey=='StaticAssetsBucketName'].OutputValue" \
  --output text)

aws s3 rm "s3://$static_bucket" --recursive
```
