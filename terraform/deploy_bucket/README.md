# Terraform state bucket

Creates the S3 bucket and DynamoDB table used by `terraform/service` for remote state and locking.

**One-time setup:**

1. From this directory: `terraform init && terraform apply`
2. Then from `terraform/service`: `terraform init` (to configure the S3 backend), then `terraform plan` / `terraform apply`

If you use a different bucket name or region, set `state_bucket_name` / `aws_region` here and ensure `terraform/service/versions.tf` backend block uses the same bucket name and region.

**Migrating existing local state:** After `terraform init` in `service/`, Terraform will prompt to copy existing state to the new backend; answer yes to migrate.
