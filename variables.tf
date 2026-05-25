variable "name_prefix" {
  description = "Prefix for all resource names. Must be unique per deployment."
  type        = string
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "opensearch_endpoint" {
  description = "OpenSearch Serverless collection endpoint. Leave empty on first apply; set to the value of opensearch_collection_endpoint output on second apply."
  type        = string
  default     = ""
}
