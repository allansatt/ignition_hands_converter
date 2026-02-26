terraform {
  required_version = ">= 1.0"

  backend "s3" {
    bucket = "allansattelbergrivera-ignition-hands-tfstate"
    key    = "service/terraform.tfstate"
    region = "us-east-1"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}
