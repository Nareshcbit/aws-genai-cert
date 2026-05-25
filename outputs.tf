output "bucket_name" {
  description = "Name of the S3 bucket holding source documents."
  value       = module.rag_docs_bucket.s3_bucket_id
}

output "opensearch_collection_arn" {
  description = "ARN of the OpenSearch Serverless vector collection."
  value       = aws_opensearchserverless_collection.rag_vectors.arn
}

output "opensearch_collection_endpoint" {
  description = "OpenSearch Serverless collection endpoint. Pass as opensearch_endpoint var on second apply."
  value       = aws_opensearchserverless_collection.rag_vectors.collection_endpoint
}

output "knowledge_base_id" {
  description = "ID of the Bedrock Knowledge Base."
  value       = aws_bedrockagent_knowledge_base.rag.id
}
