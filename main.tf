module "events_table" {
  source     = "./modules/dynamodb"
  table_name = "Events"
  hash_key   = "eventId"

  attributes = [
    { name = "eventId", type = "S" }
  ]

  tags = { Project = "event-ticketing-system", Table = "Events" }
}

module "registrations_table" {
  source     = "./modules/dynamodb"
  table_name = "Registrations"
  hash_key   = "registrationId"

  attributes = [
    { name = "registrationId", type = "S" },
    { name = "email", type = "S" },
    { name = "eventId", type = "S" },
    { name = "status", type = "S" }
  ]

  global_secondary_indexes = [
    {
      name     = "email-index"
      hash_key = "email"
    },
    {
      name      = "eventId-status-index"
      hash_key  = "eventId"
      range_key = "status"
    }
  ]

  tags = { Project = "event-ticketing-system", Table = "Registrations" }
}

module "events_lambda" {
  source        = "./modules/lambda"
  function_name = "events-handler"
  source_dir    = "${path.module}/lambdas/events"

  environment_variables = {
    EVENTS_TABLE = module.events_table.table_name
  }

  iam_policy_statements = [
    {
      actions   = ["dynamodb:Scan"]
      resources = [module.events_table.table_arn]
    }
  ]

  tags = { Project = "event-ticketing-system", Function = "events" }
}

module "registrations_lambda" {
  source        = "./modules/lambda"
  function_name = "registrations-handler"
  source_dir    = "${path.module}/lambdas/registrations"

  environment_variables = {
    EVENTS_TABLE        = module.events_table.table_name
    REGISTRATIONS_TABLE = module.registrations_table.table_name
  }

  iam_policy_statements = [
    {
      actions = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:Query"]
      resources = [
        module.registrations_table.table_arn,
        "${module.registrations_table.table_arn}/index/*"
      ]
    },
    {
      actions   = ["dynamodb:UpdateItem"]
      resources = [module.events_table.table_arn]
    }
  ]

  tags = { Project = "event-ticketing-system", Function = "registrations" }
}

# ---------- API Gateway (REST v1) ----------
resource "aws_api_gateway_rest_api" "this" {
  name = "event-ticketing-api"
}

# /events
resource "aws_api_gateway_resource" "events" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "events"
}

resource "aws_api_gateway_method" "get_events" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.events.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_events" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.events.id
  http_method             = aws_api_gateway_method.get_events.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.events_lambda.invoke_arn
}

# /register
resource "aws_api_gateway_resource" "register" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "register"
}

resource "aws_api_gateway_method" "post_register" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.register.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "post_register" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.register.id
  http_method             = aws_api_gateway_method.post_register.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.registrations_lambda.invoke_arn
}

# CORS preflight for /register (POST + JSON triggers a browser preflight)
resource "aws_api_gateway_method" "options_register" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.register.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_register" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.register.id
  http_method             = aws_api_gateway_method.options_register.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.registrations_lambda.invoke_arn
}

# /registrations/{email}
resource "aws_api_gateway_resource" "registrations" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "registrations"
}

resource "aws_api_gateway_resource" "registrations_email" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.registrations.id
  path_part   = "{email}"
}

resource "aws_api_gateway_method" "get_registrations" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.registrations_email.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "get_registrations" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.registrations_email.id
  http_method             = aws_api_gateway_method.get_registrations.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.registrations_lambda.invoke_arn
}

# /registration/{id}
resource "aws_api_gateway_resource" "registration" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "registration"
}

resource "aws_api_gateway_resource" "registration_id" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.registration.id
  path_part   = "{id}"
}

resource "aws_api_gateway_method" "delete_registration" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.registration_id.id
  http_method   = "DELETE"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "delete_registration" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.registration_id.id
  http_method             = aws_api_gateway_method.delete_registration.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.registrations_lambda.invoke_arn
}

# CORS preflight for /registration/{id} (DELETE triggers a browser preflight)
resource "aws_api_gateway_method" "options_registration_id" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.registration_id.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_registration_id" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.registration_id.id
  http_method             = aws_api_gateway_method.options_registration_id.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.registrations_lambda.invoke_arn
}

# deployment + stage
resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_integration.get_events,
      aws_api_gateway_integration.post_register,
      aws_api_gateway_integration.get_registrations,
      aws_api_gateway_integration.delete_registration,
      aws_api_gateway_integration.options_register,
      aws_api_gateway_integration.options_registration_id,
      aws_api_gateway_authorizer.cognito,
      aws_api_gateway_method.post_register,
      aws_api_gateway_method.get_registrations,
      aws_api_gateway_method.delete_registration,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "dev" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = "dev"
}

# Lambda resource policies
resource "aws_lambda_permission" "events" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.events_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

resource "aws_lambda_permission" "registrations" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.registrations_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

data "aws_region" "current" {}

output "api_base_url" {
  value = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${data.aws_region.current.region}.amazonaws.com/${aws_api_gateway_stage.dev.stage_name}"
}
