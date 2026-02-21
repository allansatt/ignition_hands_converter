variable "aws_region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket used for Terraform state"
  type        = string
  default     = "allansattelbergrivera-ignition-hands-tfstate"
}
