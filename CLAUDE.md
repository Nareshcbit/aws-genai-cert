# CLAUDE.md — Bedrock RAG Lab (Terraform)

This repo provisions the AWS infrastructure for a teaching lab: a Bedrock
Knowledge Base over documents in S3, backed by OpenSearch Serverless, used to
demonstrate Retrieval-Augmented Generation for AIP-C01 learners.

Read this file fully before doing anything. Follow it over your own defaults.

## Golden rules (non-negotiable)

- **NEVER run `terraform apply`, `terraform destroy`, or any `aws` command that
  mutates the account.** Stop and hand those to the human. You may run
  read-only/validation commands only (see "Allowed commands").
- **NEVER put secrets, account IDs, access keys, or ARNs with account numbers
  in the code.** Use variables and data sources. No hardcoded `123456789012`.
- **Plan before writing.** On any non-trivial task, first read the existing
  files and state your plan. Do not write or edit files until I approve the plan.
- **Work in small, committed steps.** One coherent change per session
  (e.g. "versions + S3 + IAM"), validate, then stop for review. Do not build
  the entire repo in one shot.
- If a requirement is ambiguous, ask one question — do not invent the
  requirement and proceed.

## Allowed commands (run freely, no need to ask)

- `terraform init`
- `terraform validate`
- `terraform fmt`
- `terraform plan` (read-only; review output, never auto-apply)
- `git status`, `git diff`, `git add`, `git commit`
- reading files, listing directories

Anything that changes AWS state or pushes to a remote: propose it, don't run it.

## Verification loop (do this every time you write HCL)

After writing or editing any `.tf` file:
1. `terraform fmt`
2. `terraform init` (if providers/modules changed)
3. `terraform validate`
4. Fix every error and re-run until `validate` passes cleanly.
5. Only then show me the diff and summarize what changed.

Treat `validate` (and `plan`, when I ask) as your tests. Don't declare a task
done until validate is green.

## Provider & version conventions

- AWS provider pinned to `~> 5.x` in `versions.tf`. Do not use arguments that
  don't exist in that major version.
- Terraform `>= 1.5`.
- Region is a variable (`var.region`), default `us-east-1`. Never hardcode a
  region inside a resource.
- **The Bedrock (`aws_bedrockagent_*`) and OpenSearch Serverless
  (`aws_opensearchserverless_*`) resources are newer and change often. Check the
  current AWS provider registry docs for their exact argument names before
  writing them — do not rely on memory. If you're unsure of an argument, say so
  rather than guessing.**

## Modules vs. raw resources (read carefully)

Goal: **least code that is still clear and correct.** Don't write boilerplate by
hand when a trusted module already does it well — but don't force a module where
none fits.

- **Prefer the official `terraform-aws-modules/*` registry modules** for mature,
  boilerplate-heavy resources: S3 bucket, IAM roles/policies, and (if ever
  needed) VPC. Pin every module to a specific version.
  - S3 → `terraform-aws-modules/s3-bucket/aws`
  - IAM role → `terraform-aws-modules/iam/aws` (the appropriate submodule)
- **Write plain `resource` blocks** for OpenSearch Serverless and the Bedrock
  Knowledge Base / data source. There is no mature community module for these,
  and they change often — a hand-written resource is clearer and safer here than
  a homegrown wrapper module. **Do NOT invent a custom module to wrap them** just
  to satisfy a "use modules" preference; that adds code, not removes it.
- Don't pull in a module you'd use less than ~70% of. A module you immediately
  override half of is worse than the raw resource.
- Favor the fewest moving parts overall. If raw resources are genuinely simpler
  for a given piece, say so and use them — flag the tradeoff, don't pad the code.

## Structure & naming

- Single root module. No nested modules unless I ask.
- Files: `versions.tf`, `variables.tf`, `main.tf` (or split by concern:
  `s3.tf`, `iam.tf`, `opensearch.tf`, `bedrock.tf`), `outputs.tf`.
- Resource names: `snake_case`, descriptive (`aws_s3_bucket.rag_docs`, not
  `aws_s3_bucket.b`).
- A `name_prefix` variable feeds all resource names so the lab can be deployed
  multiple times without collisions.
- Tag every taggable resource with:
  `Project = "cloudcraft-rag-lab"`, `ManagedBy = "terraform"`.
  Use a `default_tags` block in the provider rather than repeating tags.

## What to build (the resource list)

When asked to build the lab, the target is:

1. **S3 bucket** for source documents — via `terraform-aws-modules/s3-bucket/aws`:
   versioning enabled, public access fully blocked, named from `name_prefix`.
2. **IAM role** via `terraform-aws-modules/iam/aws` — assumable by
   `bedrock.amazonaws.com`, least-privilege: read the S3 bucket, plus the
   permissions the Knowledge Base needs to call the embedding model and the
   OpenSearch Serverless collection. Scope to this bucket/collection — no
   `"Resource": "*"` unless the API genuinely requires it (and flag it if so).
3. **OpenSearch Serverless** — raw `resource` blocks. A `VECTORSEARCH`
   collection plus its required encryption, network, and data-access policies.
   Mind the ordering: policies and collection must exist before the Knowledge
   Base references them — use explicit `depends_on` where the graph isn't obvious.
4. **Bedrock Knowledge Base** — raw `resource` blocks
   (`aws_bedrockagent_knowledge_base` + data source) using Titan Text
   Embeddings V2, pointing at the S3 bucket.

## Outputs (always expose)

- `knowledge_base_id`
- `bucket_name`
- `opensearch_collection_arn`

These are what the learner's notebook reads after the stack is up.

## Cost & safety notes (state these back to me, don't act on them)

- OpenSearch Serverless bills a minimum OCU capacity for as long as the
  collection exists. When you write docs/README, remind the learner to destroy
  the stack after the lab. Do not run destroy yourself.
- Before I apply anything, I will read the `plan` output. Your job is to make
  the plan correct and minimal, not to run it.

## Out of scope (don't touch unless asked)

- Remote state backend (S3/DynamoDB) — leave state local for the lab.
- CI/CD, OIDC roles, GitHub Actions.
- The notebook and lesson content — this repo is infrastructure only.