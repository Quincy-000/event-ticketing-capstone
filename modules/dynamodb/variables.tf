variable "table_name" {
  description = "Name of the DynamoDB table"
  type        = string
}

variable "hash_key" {
  description = "Partition key attribute name"
  type        = string
}

variable "attributes" {
  description = "List of attribute definitions used as keys or GSI keys (name + type: S/N/B)"
  type = list(object({
    name = string
    type = string
  }))
}

variable "global_secondary_indexes" {
  description = "List of GSIs: name, hash_key, and optional range_key"
  type = list(object({
    name      = string
    hash_key  = string
    range_key = optional(string)
  }))
  default = []
}

variable "billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "tags" {
  description = "Tags applied to the table"
  type        = map(string)
  default     = {}
}
