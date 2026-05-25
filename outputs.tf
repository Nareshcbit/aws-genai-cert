output "bucket_name" {
  description = "Name of the S3 bucket holding source documents."
  value       = module.rag_docs_bucket.s3_bucket_id
}

output "opensearch_collection_arn" {
  description = "ARN of the OpenSearch Serverless vector collection."
  value       = aws_opensearchserverless_collection.rag_vectors.arn
}

# knowledge_base_id added in Session 3 (bedrock.tf)
