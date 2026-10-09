locals {
  github_repo = "mikk5394@31307509/aws-terraform-cicd@1408606083"
}

#Read-only role for the pipeline, used for plan on PRs and main
resource "aws_iam_role" "plan" {
  name = "gha-terraform-plan"

  #Only GitHub Actions from this repo, on a PR or main, can use it
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = [
            "repo:${local.github_repo}:pull_request",
            "repo:${local.github_repo}:ref:refs/heads/main",
          ]
        }
      }
    }]
  })
}

#Plan needs to read everything, but change nothing
resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

#An exception - plan locks the state while it runs
resource "aws_iam_role_policy" "plan_state_lock" {
  name = "terraform-state-lock"
  role = aws_iam_role.plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = "${aws_s3_bucket.tfstate.arn}/*.tflock"
    }]
  })
}

#Apply role . can change infrastructure, but only after approval in GitHub
resource "aws_iam_role" "apply" {
  name = "gha-terraform-apply"

  #Only jobs running in the protected "production" environment
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${local.github_repo}:environment:production"
        }
      }
    }]
  })
}

#Enough to manage VPC, subnets, security groups and EC2, but no IAM
resource "aws_iam_role_policy_attachment" "apply_ec2" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

#Read and write the state (and its lock file)
resource "aws_iam_role_policy" "apply_state" {
  name = "terraform-state"
  role = aws_iam_role.apply.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.tfstate.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.tfstate.arn}/*"
      },
    ]
  })
}