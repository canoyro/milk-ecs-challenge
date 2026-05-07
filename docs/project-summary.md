# Project Summary

## Overview

This project deploys a simple containerized web application on AWS ECS using the EC2 launch type. The stack is defined with CloudFormation, runs two ECS tasks across two EC2 container instances, and exposes the app through an internet-facing Application Load Balancer.

The README contains the operational commands. This file summarizes the implementation, design choices, and review evidence.

## Architecture

- CloudFormation template: `ecs-webapp.yaml`
- Parameters file: `parameters.json`
- Application source: `app/`
- Deployment automation: `.github/workflows/`

The stack creates:

- ECS cluster using EC2 launch type
- Auto Scaling Group with desired capacity `2`
- ECS capacity provider
- ECS task definition and service with desired count `2`
- Placement strategy to spread tasks across Availability Zones and instances
- Application Load Balancer and target group health checks
- CloudWatch container logs
- ECR repository for the application image
- S3 bucket for static assets under `assets/`
- CloudFront distribution for static asset delivery

The app renders runtime identifiers such as task ID, container instance, Availability Zone, hostname, app version, and image tag. This makes load balancing easy to verify through repeated requests to the ALB.

## Requirements Covered

| Requirement | Implementation |
| --- | --- |
| Containerized web app | Nginx-based Docker app in `app/` |
| ECS EC2 launch type | ECS cluster, EC2 launch template, ASG, capacity provider, task definition, and service |
| Two container instances | ASG desired capacity is `2` |
| Two running tasks | ECS service desired count is `2` |
| Load balancing | Internet-facing ALB forwards traffic to ECS tasks |
| Infrastructure as code | AWS resources are defined in CloudFormation |
| Logging | Container logs are sent to CloudWatch Logs |
| ECR | App images are built and pushed to ECR |
| S3 static assets | CSS and logo assets are stored in S3 |
| CloudFront | Static assets are served through CloudFront with S3 Origin Access Control |
| CI/CD | GitHub Actions deploy infrastructure and app changes |

## Deployment Flow

Infrastructure and app releases are separated.

`deploy-infra.yml` runs for infrastructure changes and deploys CloudFormation.

`deploy-app.yml` runs for app changes. It syncs static assets to S3, builds the Docker image, tags it with the Git commit SHA, pushes it to ECR, and redeploys the ECS service by updating the `ContainerImage` parameter.

The deployed image uses an immutable Git SHA tag instead of `latest`, so each running task can be traced back to a specific commit.

## Security Notes

- GitHub Actions uses OIDC to assume an AWS IAM role.
- No long-lived AWS keys are required in GitHub.
- ECR scan-on-push is enabled.
- S3 server-side encryption is enabled.
- CloudFront Origin Access Control is used for S3 asset reads.
- Container logs have a short CloudWatch retention period.

## Tradeoffs And Future Improvements

- ECS instances currently run in public subnets for a simple, verifiable challenge deployment. A production version would usually place them in private subnets.
- The ALB currently serves HTTP only. HTTPS should be added for production by using a real domain, an ACM certificate, a `443` listener, and HTTP-to-HTTPS redirect.
- CloudFront is used for small static demo assets, so the performance gain is limited, but it demonstrates the production pattern for serving static files outside the application containers.

## Review Evidence

Recommended evidence to include:

- GitHub repository link
- Pull request links
- Successful GitHub Actions workflow runs
- CloudFormation stack outputs
- ECS service showing `2` running tasks
- ECS cluster showing `2` registered container instances
- ALB target group showing `2` healthy targets
- ECR repository showing immutable Git SHA image tags
- S3 bucket showing files under `assets/`
- CloudFront distribution serving the static asset URL
- Browser screenshot of the app
- Repeated `curl` output showing different task or host identifiers

If live AWS review is needed, use a temporary read-only role or a guided walkthrough rather than broad console access.
