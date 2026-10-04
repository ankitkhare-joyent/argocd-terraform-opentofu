# Local state keeps the lab self-contained. It is still encrypted (see versions.tf).
terraform {
  backend "local" {
    path = "../../../.state/20-openbao-config.tfstate"
  }
}

# Production shape, for reference. S3 now locks natively with a lock file, so
# the old DynamoDB lock table is no longer needed (OpenTofu 1.10+):
#
# terraform {
#   backend "s3" {
#     bucket       = "acme-platform-tofu-state"
#     key          = "platform/prod/20-openbao-config.tfstate"
#     region       = "eu-west-1"
#     use_lockfile = true
#   }
# }
