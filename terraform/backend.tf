# S3 backend with DynamoDB state locking.
# The S3 bucket and DynamoDB table must be created before first use.
# See RUNBOOK.md for bootstrap instructions.
terraform {
  backend "s3" {
    bucket         = "tf-backend-252147079828-ap-south-1-an"
    key            = "flask-app/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "tf-state-lock"
    encrypt        = true
  }
}
