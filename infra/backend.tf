terraform {
  backend "s3" {
    bucket       = "mikk5394-aws-terraform-cicd-tfstate"
    key          = "infra/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}