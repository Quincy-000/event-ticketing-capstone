resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    # live TLS leaf cert at token.actions.githubusercontent.com (verified 2026-08)
    "227203b5317f3818cab5b5ce596132bf36748c0e",
    # token-signing certs advertised in the JWKS (.well-known/jwks x5c)
    "ca435a638a8cfed6b89364e064e08460b91c6250",
    "38e9b30b3a023a1b72309921a69a42fcc496c42c",
    "4f3e9ad8c9a6f5eb3173006f4fa630e28f43dce9",
    # historical GitHub thumbprints kept for rotation overlap
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

resource "aws_iam_role" "cd" {
  name = "event-ticketing-cd-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # GitHub mints an environment-scoped sub when the job runs under an
          # environment (production) — and a ref-scoped sub for plain pushes.
          # Accept both; both are pinned to this repo only.
          "token.actions.githubusercontent.com:sub" = [
            "repo:Quincy-000/event-ticketing-capstone:ref:refs/heads/main",
            "repo:Quincy-000/event-ticketing-capstone:environment:production",
          ]
        }
      }
    }]
  })

  # The CD role runs `terraform apply` (infra + Lambda code) and syncs the
  # frontend. Scope: one statement per service the stack manages — broad
  # within each service, nothing outside them.
  inline_policy {
    name = "cd-deploy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "TerraformManagedServices"
          Effect = "Allow"
          Action = [
            "apigateway:*", "lambda:*", "dynamodb:*", "s3:*",
            "cognito-idp:*", "cloudfront:*", "iam:*", "sns:*",
            "cloudwatch:*", "logs:*", "budgets:*",
          ]
          Resource = ["*"]
        },
        {
          Sid      = "TerraformBasics"
          Effect   = "Allow"
          Action   = ["sts:GetCallerIdentity"]
          Resource = ["*"]
        },
      ]
    })
  }
}

output "cd_role_arn" {
  value = aws_iam_role.cd.arn
}
