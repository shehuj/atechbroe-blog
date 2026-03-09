provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "atechbroe-blog"
      ManagedBy   = "terraform"
      Environment = var.environment
      Repository  = "atechbroe-blog"
    }
  }
}
