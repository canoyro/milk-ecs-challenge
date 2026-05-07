# ECS EC2 Web App Stack

This project deploys the core MILK Books DevOps challenge stack with AWS CloudFormation. It creates an ECS cluster using the EC2 launch type, runs a simple containerized web application, spreads two service tasks across two ECS container instances, and exposes the service through an Application Load Balancer.

Bonus services such as ECR, S3, and CloudFront are intentionally deferred until the core stack is working.

## Architecture

- Existing VPC, public subnets, and security group are supplied through `parameters.json`.
- The public subnets must be in different Availability Zones because the Application Load Balancer cannot attach to multiple subnets in the same Availability Zone.
- Stack-created resources use the CloudFormation stack name as their name prefix, for example `milk-ecs-webapp-cluster`, `milk-ecs-webapp-asg`, and `milk-ecs-webapp-alb`.
- An Auto Scaling Group launches two ECS optimized Amazon Linux 2 EC2 instances.
- The ECS agent registers both instances into the ECS cluster during boot.
- An ECS capacity provider connects the Auto Scaling Group to the cluster.
- An ECS service runs two copies of the `web` task and uses placement strategies to spread tasks across Availability Zones and EC2 instances where capacity allows.
- An internet-facing Application Load Balancer forwards HTTP traffic to the ECS tasks.
- Container logs are written to CloudWatch Logs.

## Prerequisites

- AWS CLI v2 installed and configured.
- An AWS identity with permission to create CloudFormation, ECS, EC2, Auto Scaling, IAM, Elastic Load Balancing, CloudWatch Logs, and SSM parameter resources.
- Existing VPC, public subnets, and security group.
- The security group must allow inbound HTTP traffic to the load balancer and allow the load balancer to reach port 80 on the ECS instances.

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
  --subnet-ids subnet-0f3b2f2ec01dcdc0e subnet-037ae5a57a4969697 \
  --query "Subnets[].{SubnetId:SubnetId,AvailabilityZone:AvailabilityZone,MapPublicIpOnLaunch:MapPublicIpOnLaunch}" \
  --output table
```

If both `PubSubnets` are in the same Availability Zone, replace one of them in `parameters.json` with a public subnet from a different Availability Zone in the same VPC.

## Deploy

```bash
aws cloudformation deploy \
  --stack-name milk-ecs-webapp \
  --template-file ecs-webapp.yaml \
  --parameter-overrides file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM
```

Get the application URL:

```bash
aws cloudformation describe-stacks \
  --stack-name milk-ecs-webapp \
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

## Roll Out A New Image

Change `ContainerImage` in `parameters.json` to a new immutable image tag, then redeploy:

```bash
aws cloudformation deploy \
  --stack-name milk-ecs-webapp \
  --template-file ecs-webapp.yaml \
  --parameter-overrides file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM
```

CloudFormation registers a new task definition revision and ECS rolls the service to the new image.

## Validate

```bash
aws cloudformation validate-template --template-body file://ecs-webapp.yaml
```

## Clean Up

```bash
aws cloudformation delete-stack --stack-name milk-ecs-webapp
```
