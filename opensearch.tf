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

# Data-access policy — grants the Bedrock KB role and the Terraform caller
# read/write access on indices (caller needs it to create the vector index)
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
    Principal = [aws_iam_role.bedrock_kb.arn, data.aws_caller_identity.current.arn]
  }])
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

# Vector index — created via local Python/boto3 so the endpoint can be read
# directly from the collection resource without a second provider or two-step apply.
# Recreated automatically if the collection is replaced (triggers_replace).
resource "terraform_data" "vector_index" {
  triggers_replace = [aws_opensearchserverless_collection.rag_vectors.id]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      AOSS_ENDPOINT   = aws_opensearchserverless_collection.rag_vectors.collection_endpoint
      INDEX_NAME      = "${var.name_prefix}-index"
      AWS_REGION_NAME = var.region
    }
    command = <<-BASH
      python3 - <<'PYEOF'
import boto3, json, sys, os
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
import urllib.request, urllib.error

endpoint = os.environ["AOSS_ENDPOINT"]
index    = os.environ["INDEX_NAME"]
region   = os.environ["AWS_REGION_NAME"]

url  = f"{endpoint}/{index}"
body = json.dumps({
    "settings": {"index.knn": True},
    "mappings": {
        "properties": {
            "bedrock-knowledge-base-default-vector": {
                "type": "knn_vector",
                "dimension": 1024,
                "method": {
                    "name": "hnsw",
                    "engine": "faiss",
                    "space_type": "l2",
                    "parameters": {"ef_construction": 512, "m": 16}
                }
            },
            "AMAZON_BEDROCK_TEXT_CHUNK": {"type": "text"},
            "AMAZON_BEDROCK_METADATA":   {"type": "text", "index": "false"}
        }
    }
}).encode("utf-8")

session = boto3.Session()
creds   = session.get_credentials().get_frozen_credentials()
host    = endpoint.replace("https://", "")

aws_req = AWSRequest(
    method="PUT", url=url, data=body,
    headers={"Content-Type": "application/json", "Host": host}
)
SigV4Auth(creds, "aoss", region).add_auth(aws_req)

# Exclude Host — urllib sets it automatically from the URL
headers  = {k: v for k, v in aws_req.headers.items() if k.lower() != "host"}
http_req = urllib.request.Request(url, data=body, headers=headers, method="PUT")

try:
    with urllib.request.urlopen(http_req) as r:
        print(r.read().decode())
except urllib.error.HTTPError as e:
    err = e.read().decode()
    if "resource_already_exists_exception" in err.lower():
        print("Index already exists — OK")
    else:
        print(err, file=sys.stderr)
        sys.exit(1)
PYEOF
    BASH
  }
}
