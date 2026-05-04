# Team Update — Flask API Infrastructure Rollout

We're deploying a new Flask REST API on ECS Fargate behind an ALB, fully provisioned with Terraform. This sets up the foundational infrastructure pattern we'll use for future services.

## Key Changes
- New VPC with public/private subnet architecture across 2 AZs
- ECS Fargate cluster running containerized Flask app
- ALB with health check routing to `/health`
- Terraform remote state with S3 + DynamoDB locking
- CI/CD pipeline via GitHub Actions (plan on PR, plan on merge to main)

## Rollout Schedule
- **Dev** — Wednesday 10:00 AM ET
- **Staging** — Wednesday 2:00 PM ET (after dev verification)
- **Prod** — Thursday 10:00 AM ET (manual approval required)

## Links
- **PR:** https://github.com/captain-omkar/flask-ecs-infra/pulls
- **Runbook:** `RUNBOOK.md` in repo root
- **Architecture:** `README.md` → Architecture section
- **Monitoring:** CloudWatch log group `/ecs/newrelic-demo-<env>`

## Risks
Minimal. The app is stateless and the infrastructure is isolated per environment. Rollback takes under 5 minutes via ECS task definition revert or `terraform apply` of previous state.

## Contact
Owner: @captain-omkar
Questions → drop them in the thread or ping me directly.
