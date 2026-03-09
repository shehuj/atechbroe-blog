terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Partial backend config — bucket/region/table passed via -backend-config
  # in the GitHub Actions workflow (see .github/workflows/terraform.yml)
  backend "s3" {
    key     = "ghost-blog/terraform.tfstate"
    encrypt = true
  }
}
