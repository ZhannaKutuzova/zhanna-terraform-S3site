provider "aws" {
  region = "us-east-1" # Or your preferred region
}

# --- Configuration Variables ---
variable "bucket_name_prefix" {
  description = "A unique prefix for the S3 bucket name."
  type        = string
  default     = "zhanna-test555-site" # Customize if needed
}

variable "github_repo_owner" {
  description = "The owner of the GitHub repository."
  type        = string
  default     = "ZhannaKutuzova"
}

variable "github_repo_name" {
  description = "The name of the GitHub repository."
  type        = string
  default     = "zhanna-amazon-S3site"
}

variable "github_repo_branch" {
  description = "The branch of the GitHub repository to use."
  type        = string
  default     = "main" # Or "master" or other branch name
}

# --- S3 Bucket Setup ---
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "website_bucket" {
  bucket = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"
  tags = {
    Name        = "S3 Static Website Bucket for ${var.github_repo_name}"
    Environment = "Demo"
    SourceRepo  = "github.com/${var.github_repo_owner}/${var.github_repo_name}"
  }
}

resource "aws_s3_bucket_public_access_block" "website_bucket_access_block" {
  bucket = aws_s3_bucket.website_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "website_config" {
  bucket = aws_s3_bucket.website_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    # Assuming you might add an error.html to your repo later
    # If not, you can remove this or point to index.html
    key = "error.html"
  }
  depends_on = [aws_s3_bucket_public_access_block.website_bucket_access_block]
}

data "aws_iam_policy_document" "public_read_policy" {
  statement {
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${aws_s3_bucket.website_bucket.arn}/*",
    ]
  }
}

resource "aws_s3_bucket_policy" "website_bucket_policy" {
  bucket = aws_s3_bucket.website_bucket.id
  policy = data.aws_iam_policy_document.public_read_policy.json
  depends_on = [
    aws_s3_bucket_public_access_block.website_bucket_access_block,
    # Ensure website config is set before policy in case it affects how S3 evaluates policy
    aws_s3_bucket_website_configuration.website_config
  ]
}

# --- Fetch Files from GitHub ---

data "http" "index_html_content" {
  url = "https://raw.githubusercontent.com/${var.github_repo_owner}/${var.github_repo_name}/${var.github_repo_branch}/index.html"
  # Optional: Add request_headers if needed for private repos (not for this public one)
  # request_headers = {
  #   Authorization = "token YOUR_GITHUB_PAT"
  # }
}

data "http" "script_js_content" {
  url = "https://raw.githubusercontent.com/${var.github_repo_owner}/${var.github_repo_name}/${var.github_repo_branch}/script.js"
}

data "http" "style_css_content" {
  url = "https://raw.githubusercontent.com/${var.github_repo_owner}/${var.github_repo_name}/${var.github_repo_branch}/style.css"
}

# Placeholder for error.html - if you add one to your repo, uncomment and fetch it
# data "http" "error_html_content" {
#   url = "https://raw.githubusercontent.com/${var.github_repo_owner}/${var.github_repo_name}/${var.github_repo_branch}/error.html"
# }

# --- Upload Fetched Files to S3 ---

resource "aws_s3_object" "index_document" {
  bucket       = aws_s3_bucket.website_bucket.id
  key          = "index.html"
  content      = data.http.index_html_content.response_body # Use response_body for binary/text content
  content_type = "text/html"
  # Using md5 of the content as etag ensures the object is updated if the content changes in GitHub
  etag = md5(data.http.index_html_content.response_body)
  depends_on = [aws_s3_bucket_policy.website_bucket_policy] # Ensure bucket policy is set
}

resource "aws_s3_object" "script_js" {
  bucket       = aws_s3_bucket.website_bucket.id
  key          = "script.js"
  content      = data.http.script_js_content.response_body
  content_type = "application/javascript"
  etag         = md5(data.http.script_js_content.response_body)
  depends_on   = [aws_s3_bucket_policy.website_bucket_policy]
}

resource "aws_s3_object" "style_css" {
  bucket       = aws_s3_bucket.website_bucket.id
  key          = "style.css"
  content      = data.http.style_css_content.response_body
  content_type = "text/css"
  etag         = md5(data.http.style_css_content.response_body)
  depends_on   = [aws_s3_bucket_policy.website_bucket_policy]
}

# If you create an error.html in your GitHub repo and uncomment its data source:
resource "aws_s3_object" "error_document" {
  # Only create this if you have an error.html. For now, we'll make a dummy one.
  # If you fetch from GitHub, use:
  # content      = data.http.error_html_content.response_body
  # etag         = md5(data.http.error_html_content.response_body)

  bucket       = aws_s3_bucket.website_bucket.id
  key          = "error.html" # Must match error_document key in website_config
  content_type = "text/html"
  content      = <<-EOT
  <!DOCTYPE html>
  <html>
  <head><title>404 Not Found</title></head>
  <body><h1>404 Not Found</h1><p>The page you requested could not be found.</p></body>
  </html>
  EOT
  etag = md5(<<-EOT
  <!DOCTYPE html>
  <html>
  <head><title>404 Not Found</title></head>
  <body><h1>404 Not Found</h1><p>The page you requested could not be found.</p></body>
  </html>
  EOT
  )
  depends_on = [aws_s3_bucket_policy.website_bucket_policy]
}


# --- Outputs ---
output "s3_bucket_name" {
  description = "The name of the S3 bucket."
  value       = aws_s3_bucket.website_bucket.bucket
}

output "website_endpoint" {
  description = "The S3 static website endpoint URL (use this for browsing)."
  value       = "http://${aws_s3_bucket_website_configuration.website_config.website_endpoint}"
}

output "website_domain_name" {
  description = "The S3 static website domain name (used for CloudFront, Route53 alias)."
  value       = aws_s3_bucket_website_configuration.website_config.website_domain
}
