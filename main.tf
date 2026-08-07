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
