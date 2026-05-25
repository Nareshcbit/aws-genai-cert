data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "bedrock_kb_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "bedrock_kb_permissions" {
  # S3 read — scoped to the specific bucket created in s3.tf
  statement {
    sid    = "S3ListBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [
      module.rag_docs_bucket.s3_bucket_arn,
    ]
  }

  statement {
    sid    = "S3GetObject"
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${module.rag_docs_bucket.s3_bucket_arn}/*",
    ]
  }

  # Bedrock embedding model — Titan Text Embeddings V2
  statement {
    sid    = "BedrockInvokeEmbeddingModel"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
    ]
    resources = [
      "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v2:0",
    ]
  }

  # OpenSearch Serverless — collection/* wildcard because the collection ID
  # is auto-generated and won't be known until Session 2. Tighten to the
  # specific collection ARN in Session 2 once it exists.
  statement {
    sid    = "OpenSearchServerlessAccess"
    effect = "Allow"
    actions = [
      "aoss:APIAccessAll",
    ]
    resources = [
      "arn:aws:aoss:${var.region}:${data.aws_caller_identity.current.account_id}:collection/*",
    ]
  }
}

resource "aws_iam_role" "bedrock_kb" {
  name               = "${var.name_prefix}-bedrock-kb-role"
  assume_role_policy = data.aws_iam_policy_document.bedrock_kb_trust.json
}

resource "aws_iam_role_policy" "bedrock_kb" {
  name   = "${var.name_prefix}-bedrock-kb-policy"
  role   = aws_iam_role.bedrock_kb.id
  policy = data.aws_iam_policy_document.bedrock_kb_permissions.json
}
