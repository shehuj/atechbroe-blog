terraform {
  # S3 remote state with DynamoDB locking.
  # Bucket, region, and lock table are passed at init time via -backend-config
  # so they never need to be hardcoded here.
  #
  # Local init example:
  #   terraform init \
  #     -backend-config="bucket=ec2-shutdown-lambda-bucket" \
  #     -backend-config="region=us-east-1" \
  #     -backend-config="dynamodb_table=dyning_table"
  #
  # In CI the GitHub Actions workflow passes these via secrets (see terraform.yml).
  backend "s3" {
    key     = "ghost-blog/terraform.tfstate"
    encrypt = true
  }
}
