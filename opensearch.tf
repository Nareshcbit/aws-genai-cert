# Bedrock requires the vector index to exist before the Knowledge Base can be
# created. This provider creates it. Two-step apply is required:
#
#   Step 1: terraform apply -var="name_prefix=..." (creates collection)
#   Step 2: ENDPOINT=$(terraform output -raw opensearch_collection_endpoint)
#           terraform apply -var="name_prefix=..." -var="opensearch_endpoint=$ENDPOINT"
#
provider "opensearch" {
  url                   = var.opensearch_endpoint != "" ? var.opensearch_endpoint : "https://placeholder.${var.region}.aoss.amazonaws.com"
  aws_region            = var.region
  sign_aws_requests     = true
  aws_signature_service = "aoss"
  healthcheck           = false
}

locals {
  collection_name = "${var.name_prefix}-vectors"
}

# Encryption policy — AWS-owned key, scoped to this collection only
resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "${var.name_prefix}-enc"
  type = "encryption"
  policy = jsonencode({
    Rules = [{
      ResourceType = "collection"
      Resource     = ["collection/${local.collection_name}"]
    }]
    AWSOwnedKey = true
  })
}

# Network policy — public access for the teaching lab endpoint and dashboard
resource "aws_opensearchserverless_security_policy" "network" {
  name = "${var.name_prefix}-net"
  type = "network"
  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.collection_name}"]
      },
      {
        ResourceType = "dashboard"
        Resource     = ["collection/${local.collection_name}"]
      },
    ]
    AllowFromPublic = true
  }])
}

# Data-access policy — grants the Bedrock KB role read/write on indices
resource "aws_opensearchserverless_access_policy" "bedrock_kb" {
  name = "${var.name_prefix}-data"
  type = "data"
  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.collection_name}"]
        Permission = [
          "aoss:CreateCollectionItems",
          "aoss:DeleteCollectionItems",
          "aoss:UpdateCollectionItems",
          "aoss:DescribeCollectionItems",
        ]
      },
      {
        ResourceType = "index"
        Resource     = ["index/${local.collection_name}/*"]
        Permission = [
          "aoss:CreateIndex",
          "aoss:DeleteIndex",
          "aoss:UpdateIndex",
          "aoss:DescribeIndex",
          "aoss:ReadDocument",
          "aoss:WriteDocument",
        ]
      },
    ]
    # bedrock_kb role: runtime access for the KB service
    # current caller: Terraform executor needs access to create the index
    Principal = [aws_iam_role.bedrock_kb.arn, data.aws_caller_identity.current.arn]
  }])
}

# Vector index — must exist before the Bedrock Knowledge Base is created.
# Titan Text Embeddings V2 outputs 1024 dimensions.
resource "opensearch_index" "rag_vectors" {
  name      = "${var.name_prefix}-index"
  index_knn = true

  mappings = jsonencode({
    properties = {
      "bedrock-knowledge-base-default-vector" = {
        type      = "knn_vector"
        dimension = 1024
        method = {
          name       = "hnsw"
          engine     = "faiss"
          space_type = "l2"
          parameters = {
            ef_construction = 512
            m               = 16
          }
        }
      }
      "AMAZON_BEDROCK_TEXT_CHUNK" = { type = "text" }
      "AMAZON_BEDROCK_METADATA"   = { type = "text", index = "false" }
    }
  })

  depends_on = [aws_opensearchserverless_collection.rag_vectors]
}

# Collection — must come after all three policies
resource "aws_opensearchserverless_collection" "rag_vectors" {
  name = local.collection_name
  type = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    aws_opensearchserverless_access_policy.bedrock_kb,
  ]
}
