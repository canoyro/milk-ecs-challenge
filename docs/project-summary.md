# Project Summary

## Purpose

This project implements the MILK Books DevOps challenge as a deployable AWS ECS web application stack. The goal was to use infrastructure as code to run a simple containerized web app on ECS with the EC2 launch type, expose it through an Application Load Balancer, and demonstrate operational practices around deployment, verification, and incremental delivery.

This document is written for a CTO or technical hiring reviewer. The README remains the operator guide with commands and day-to-day usage details.

## Architecture

The stack is defined in `ecs-webapp.yaml` and deployed with AWS CloudFormation. It uses an existing VPC, public subnets, and security group supplied through `parameters.json`.

The CloudFormation stack creates:

- An ECS cluster using the EC2 launch type.
- An Auto Scaling Group with desired capacity `2`.
- ECS optimized Amazon Linux 2 instances resolved through the AWS public SSM AMI parameter.
- An ECS capacity provider backed by the Auto Scaling Group.
- An ECS task definition and service running two web tasks.
- ECS placement strategies to spread tasks across Availability Zones and container instances where capacity allows.
- An internet-facing Application Load Balancer with an HTTP listener.
- An ALB target group with HTTP health checks.
- CloudWatch Logs for container logs.
- An ECR repository for the custom application image.
- An S3 bucket for static assets under the `assets/` prefix.

The application is a small Nginx-based container in `app/`. At startup it renders an HTML page with runtime metadata such as task ID, container instance, Availability Zone, hostname, app version, and image tag. These values make it easy to verify that the ALB is distributing traffic across different ECS tasks.

## Requirement Mapping

| Requirement | Implementation |
| --- | --- |
| Deploy a containerized web application | The `app/` Docker image runs through an ECS task definition. |
| Use ECS with EC2 launch type | The stack creates an ECS cluster, EC2 instance role, launch template, Auto Scaling Group, capacity provider, task definition, and ECS service. |
| Run across two ECS container instances | The Auto Scaling Group desired capacity is `2`, and the ECS service desired count is `2`. |
| Expose the app externally | An internet-facing Application Load Balancer forwards HTTP traffic to the ECS service. |
| Use infrastructure as code | All AWS resources are defined in `ecs-webapp.yaml`. |
| Add load balancing verification | The app displays task and host identifiers so repeated requests can confirm balancing behavior. |
| Add logging | Container logs are sent to CloudWatch Logs. |
| Use ECR | The stack creates an ECR repository, and the app workflow pushes images into it. |
| Use S3 for static assets | Static CSS and logo assets are synced to S3 and referenced by the running application. |
| Automate deployment | GitHub Actions builds and deploys app changes and separately deploys infrastructure changes. |

## Deployment Flow

Infrastructure and application releases are intentionally separated.

Infrastructure changes are handled by `.github/workflows/deploy-infra.yml`. It runs when `ecs-webapp.yaml`, `parameters.json`, or the workflow itself changes on `main`. It deploys CloudFormation only.

Application changes are handled by `.github/workflows/deploy-app.yml`. It runs when files under `app/`, `scripts/`, or the workflow itself change on `main`, or when manually triggered. The workflow:

1. Reads stack outputs for the ECR repository URI and S3 static asset bucket.
2. Syncs `app/assets` to the S3 asset bucket.
3. Builds the Docker image.
4. Tags the image with the first 12 characters of the Git commit SHA.
5. Optionally applies a semantic image tag for human-readable releases.
6. Pushes the image to ECR.
7. Redeploys CloudFormation with `ContainerImage` set to the immutable image URI.

The service deploys immutable Git SHA image tags rather than `latest`. This keeps each ECS task traceable to a specific source revision and makes rollback precise.

## Security And Operations

GitHub Actions uses OIDC to assume an AWS IAM role instead of storing long-lived AWS access keys. The role is expected to follow least privilege for CloudFormation deployment, ECR image pushes, S3 asset sync, and the specific AWS APIs required by the template.

The implementation uses:

- CloudFormation-managed IAM roles for ECS EC2 instances and ECS task execution.
- ECR scan-on-push for application images.
- CloudWatch Logs with a short retention period for container logs.
- S3 server-side encryption for the static asset bucket.
- Public S3 read access scoped to `assets/*` only for the demo asset-serving requirement.

For a production version, CloudFront with Origin Access Control would be preferable to public S3 object reads.

## Tradeoffs

Public subnets are used for the ECS instances in this challenge implementation to keep the environment small, easy to verify, and aligned with the provided networking constraints. A production design would usually place ECS instances in private subnets and use NAT or VPC endpoints for outbound access.

The ALB currently serves HTTP only. HTTPS would require an ACM certificate and a domain name, which can be added later through a `443` listener and HTTP-to-HTTPS redirect.

CloudFront was intentionally deferred. S3 static asset serving is implemented directly first to demonstrate the requirement without adding CDN cost and certificate/domain complexity.

## Evidence Checklist

Recommended review evidence:

- GitHub repository link.
- Pull request links for the core stack, app deployment, S3 asset serving, and documentation cleanup.
- Successful GitHub Actions run links for both infrastructure and app workflows.
- CloudFormation stack outputs showing the ALB URL, ECS cluster name, ECS service name, ECR repository URI, and S3 asset URL.
- ECS service screenshot or CLI output showing desired count `2` and running count `2`.
- ECS container instances screenshot or CLI output showing two registered container instances.
- ALB target group screenshot or CLI output showing two healthy targets.
- ECR screenshot showing immutable Git SHA image tags.
- S3 screenshot showing files under the `assets/` prefix.
- Browser screenshot of the app showing task/runtime identifiers.
- Repeated `curl` output showing different task or host identifiers through the ALB.

AWS console access should not be the primary evidence. If live review access is needed, prefer a temporary read-only role or a guided walkthrough.

## Suggested Review Narrative

This implementation prioritizes the core requirement first: a working ECS EC2 service behind an ALB, deployed through CloudFormation. Bonus items were then layered in incrementally with ECR, S3 static assets, and GitHub Actions automation. The final result demonstrates not only that the application runs, but also that it can be built, deployed, verified, and rolled forward with traceable image versions.
