variable "name_prefix" {
  description = "Prefix for all resource names. Must be unique per deployment."
  type        = string
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}
