## Overview

A minimal Python Flask REST API deployed on AWS ECS Fargate behind an Application Load Balancer, provisioned entirely with Terraform.

ECS Fargate was chosen because it provides serverless container orchestration with no EC2 instances to manage. For a stateless API like this, Fargate is right-sized — simpler and cheaper to operate than EKS, with built-in scaling primitives when needed.

## Architecture

```
Internet → ALB (public subnets) → ECS Fargate tasks (private subnets)
```

Components:

- **VPC** with 2 public and 2 private subnets across 2 AZs — provides network isolation and high availability.
- **Application Load Balancer** in public subnets — handles HTTP traffic, performs health checks against `/health`, and is ready for TLS termination and path-based routing when needed.
- **ECS Fargate** in private subnets — runs containers without direct internet exposure. Tasks pull images from ECR via NAT gateway.
- **ECR** — private Docker registry co-located with the compute, no external registry dependencies.
- **NAT Gateway** — allows private subnet tasks to reach the internet (ECR image pulls, etc.) without being publicly addressable.
- **S3 + DynamoDB backend** — enables team collaboration on Terraform state with locking to prevent concurrent modifications. Both services are free-tier eligible.

## Prerequisites

- Terraform >= 1.5
- AWS CLI v2, configured with appropriate credentials
- Docker (for building and pushing the app image)

## Usage

### Local Development

```bash
# Build and run the app locally
docker build -t newrelic-demo app/
docker run -p 8080:8080 newrelic-demo
curl http://localhost:8080/health
```

### Bootstrap Terraform Backend (One-Time)

Before the first run, create the S3 bucket and DynamoDB table for remote state:

```bash
BUCKET_NAME="tf-backend-252147079828-ap-south-1-an"
TABLE_NAME="tf-state-lock"
REGION="ap-south-1"

# Create S3 bucket
aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"
aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB lock table
aws dynamodb create-table --table-name "$TABLE_NAME" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region "$REGION"
```

### Terraform

```bash
cd terraform

# Initialize (backend config is in backend.tf)
terraform init

# Plan for a specific environment
terraform plan -var-file=../environments/dev.tfvars

# Apply
terraform apply -var-file=../environments/dev.tfvars
```

### GitHub Actions

- **Push to main** → automatically plans against prod
- **Pull request to main** → plans against dev, posts output as PR comment
- **Manual dispatch** → choose any environment (dev/staging/prod)

## Trade-offs

- **No RDS** — the app is stateless; adding a database would be unnecessary complexity.
- **No HTTPS** — production would add ACM certificate + HTTPS listener. Omitted here to keep the scope focused.
- **Single region** — multi-region adds significant complexity (Route53 failover, cross-region replication) that isn't justified for this use case.
- **No auto-scaling** — would add an ECS auto-scaling policy in production, but a fixed `desired_count` is sufficient for demonstration.
- **Single NAT Gateway** — production would use one per AZ for high availability.

## What I Would Change for Production

- **OIDC for CI/CD** — replace static AWS credentials with GitHub OIDC federation (assume role, no keys to rotate).
- **WAF** — attach AWS WAF to the ALB for rate limiting and common exploit protection.
- **Auto-scaling** — target tracking policy on ECS service based on CPU/request count.
- **Monitoring** — CloudWatch alarms on 5xx rates, task health, and CPU utilization, with SNS notifications.
- **HTTPS** — ACM certificate + Route53 DNS + HTTPS listener on the ALB.
- **Multi-region** — Route53 health-checked failover to a standby region.
- **Container image tags** — use Git SHA tags instead of `latest` for traceability.
