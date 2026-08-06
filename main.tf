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
