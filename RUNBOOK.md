# Runbook

## 1. Prerequisites

You need the following installed and configured:

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.5 | Infrastructure provisioning |
| AWS CLI | v2 | AWS authentication and ECR login |
| Docker | Latest | Building container images |

AWS permissions required:
- ECS, ECR, EC2, ELB, IAM, CloudWatch Logs, S3, DynamoDB
- Or use an admin role for non-production environments

## 2. Initial Setup

1. Clone the repository:
   ```bash
   git clone <repo-url>
   cd <repo-name>
   ```

2. Configure AWS credentials:
   ```bash
   aws configure
   # Or export environment variables:
   export AWS_ACCESS_KEY_ID=<your-key>
   export AWS_SECRET_ACCESS_KEY=<your-secret>
   export AWS_DEFAULT_REGION=ap-south-1
   ```

3. Verify access:
   ```bash
   aws sts get-caller-identity
   ```

## 3. Bootstrap Terraform Backend (One-Time)

Before the first `terraform init`, you must create the S3 bucket and DynamoDB table that store Terraform state. This is a one-time step per AWS account.

1. Create the S3 bucket:
   ```bash
   BUCKET_NAME="tf-backend-252147079828-ap-south-1-an"
   REGION="ap-south-1"

   aws s3api create-bucket \
     --bucket "$BUCKET_NAME" \
     --region "$REGION" \
     --create-bucket-configuration LocationConstraint="$REGION"
   ```

2. Enable versioning (protects against accidental state deletion):
   ```bash
   aws s3api put-bucket-versioning \
     --bucket "$BUCKET_NAME" \
     --versioning-configuration Status=Enabled
   ```

3. Enable server-side encryption:
   ```bash
   aws s3api put-bucket-encryption \
     --bucket "$BUCKET_NAME" \
     --server-side-encryption-configuration \
       '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
   ```

4. Block public access:
   ```bash
   aws s3api put-public-access-block \
     --bucket "$BUCKET_NAME" \
     --public-access-block-configuration \
       BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
   ```

5. Create the DynamoDB lock table:
   ```bash
   TABLE_NAME="tf-state-lock"

   aws dynamodb create-table \
     --table-name "$TABLE_NAME" \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST \
     --region "ap-south-1"
   ```

6. For GitHub Actions, add these secrets to your repository:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_REGION` — `ap-south-1`

## 4. Deploy to Dev

1. Build and push the Docker image:
   ```bash
   cd app
   aws ecr get-login-password --region ap-south-1 | \
     docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-south-1.amazonaws.com

   docker build -t newrelic-demo-dev .
   docker tag newrelic-demo-dev:latest <account-id>.dkr.ecr.ap-south-1.amazonaws.com/newrelic-demo-dev:latest
   docker push <account-id>.dkr.ecr.ap-south-1.amazonaws.com/newrelic-demo-dev:latest
   cd ..
   ```

2. Initialize and apply Terraform:
   ```bash
   cd terraform
   terraform init
   terraform plan -var-file=../environments/dev.tfvars
   terraform apply -var-file=../environments/dev.tfvars
   ```

3. Confirm the output shows the ALB DNS name.

## 5. Deploy to Staging

1. Repeat the Docker build/push steps from section 4, replacing `dev` with `staging` in image names.

2. Apply Terraform:
   ```bash
   cd terraform
   terraform init
   terraform plan -var-file=../environments/staging.tfvars
   terraform apply -var-file=../environments/staging.tfvars
   ```

## 6. Deploy to Prod

> **CAUTION:** Production deployment. Double-check the plan output before applying.

1. Repeat the Docker build/push steps, replacing with `prod` in image names.

2. Plan first and review carefully:
   ```bash
   cd terraform
   terraform init
   terraform plan -var-file=../environments/prod.tfvars
   ```

3. Review the plan output. Confirm no unexpected resource deletions.

4. Apply with explicit approval:
   ```bash
   terraform apply -var-file=../environments/prod.tfvars
   ```
   Type `yes` only after reviewing the plan summary.

## 7. Verify Deployment

1. Get the ALB DNS name from Terraform output:
   ```bash
   terraform output alb_dns_name
   ```

2. Test the endpoints:
   ```bash
   curl http://<alb-dns-name>/
   # Expected: {"message": "Hello, World!"}

   curl http://<alb-dns-name>/health
   # Expected: {"status": "healthy"}
   ```

3. Check ECS service status:
   ```bash
   aws ecs describe-services \
     --cluster newrelic-demo-<env>-cluster \
     --services newrelic-demo-<env>-service \
     --query 'services[0].{desired:desiredCount,running:runningCount,status:status}'
   ```

## 8. Rollback Procedure

### Option A: Terraform Rollback

1. Revert the code change and re-apply:
   ```bash
   git revert <commit-sha>
   cd terraform
   terraform apply -var-file=../environments/<env>.tfvars
   ```

### Option B: ECS Rollback (faster, image-level)

1. Find the previous task definition revision:
   ```bash
   aws ecs list-task-definitions \
     --family-prefix newrelic-demo-<env>-app \
     --sort DESC --max-items 5
   ```

2. Update the service to use the previous revision:
   ```bash
   aws ecs update-service \
     --cluster newrelic-demo-<env>-cluster \
     --service newrelic-demo-<env>-service \
     --task-definition newrelic-demo-<env>-app:<previous-revision>
   ```

3. Verify the rollback:
   ```bash
   curl http://<alb-dns-name>/health
   ```

## 9. Common Issues & Troubleshooting

### `terraform init` fails with "S3 bucket does not exist"

The backend S3 bucket hasn't been created yet. Run the bootstrap steps in section 3.

### ECS task failing to start — "image not found"

The Docker image hasn't been pushed to ECR, or the repository name doesn't match.

1. Verify the ECR repository exists:
   ```bash
   aws ecr describe-repositories --repository-names newrelic-demo-<env>
   ```
2. Verify the image is pushed:
   ```bash
   aws ecr list-images --repository-name newrelic-demo-<env>
   ```
3. If empty, rebuild and push the image (see section 4, step 1).

### ALB returning 502 Bad Gateway

The ALB can't reach healthy targets. Common causes:

1. **Health check misconfigured** — verify the target group health check path is `/health` and the container listens on port 8080.
2. **Security group issue** — ensure the ECS security group allows inbound on 8080 from the ALB security group.
3. **Task crashing** — check CloudWatch logs:
   ```bash
   aws logs tail /ecs/newrelic-demo-<env> --follow
   ```

### Terraform state lock error

Someone else is running Terraform, or a previous run crashed.

1. Check who holds the lock:
   ```bash
   aws dynamodb get-item \
     --table-name tf-state-lock \
     --key '{"LockID":{"S":"tf-backend-252147079828-ap-south-1-an/flask-app/<env>/terraform.tfstate"}}'
   ```
2. If the lock is stale, force unlock:
   ```bash
   terraform force-unlock <lock-id>
   ```

## 10. Contacts

| Role | Contact |
|------|---------|
| Infrastructure Owner | @your-name |
| On-call Escalation | #devops-oncall (Slack) |
