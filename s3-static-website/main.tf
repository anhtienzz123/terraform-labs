provider "aws" {
  region = var.aws_region
}

locals {
  static_dir = "${path.module}/static-web"
  files      = fileset(local.static_dir, "**") # all files recursively
  s3_tag = "s3-static-site"

  # Minimal MIME map — extend as needed
  mime_types = {
    ".html" = "text/html"
    ".htm"  = "text/html"
    ".css"  = "text/css"
    ".js"   = "application/javascript"
    ".json" = "application/json"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".gif"  = "image/gif"
    ".svg"  = "image/svg+xml"
    ".ico"  = "image/x-icon"
    ".txt"  = "text/plain"
    ".xml"  = "application/xml"
    ".woff" = "font/woff"
    ".woff2"= "font/woff2"
    ".ttf"  = "font/ttf"
    ".eot"  = "application/vnd.ms-fontobject"
    ".pdf"  = "application/pdf"
    ".webp" = "image/webp"
    ".map"  = "application/json"
  }
}

# 1) Bucket
resource "aws_s3_bucket" "static" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Project = local.s3_tag
  }
}

# 2) Website hosting
resource "aws_s3_bucket_website_configuration" "static" {
  bucket = aws_s3_bucket.static.bucket

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# 3) Allow public access via BUCKET POLICY (no ACLs)
#    Public access block must allow public policy to take effect
resource "aws_s3_bucket_public_access_block" "static" {
  bucket = aws_s3_bucket.static.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "static" {
  bucket = aws_s3_bucket.static.id
  
  policy = templatefile("${path.module}/s3_public_read_policy.json.tpl", {
    bucket_arn = aws_s3_bucket.static.arn
  })

  # keep this if you also use aws_s3_bucket_public_access_block and want the policy to take effect
  depends_on = [aws_s3_bucket_public_access_block.static]
}

# 4) Upload site files (no ACLs needed)
resource "aws_s3_object" "static_files" {
  # Use every file under static-web/ as an object
  for_each = {
    for f in local.files : f => f
    # skip directories; fileset returns files only, but keep this in case
    if !endswith(f, "/")
  }

  bucket = aws_s3_bucket.static.bucket
  key    = each.value
  source = "${local.static_dir}/${each.value}"

  # ensure Terraform detects content changes and re-uploads
  etag = filemd5("${local.static_dir}/${each.value}")

  # detect extension and map to a content-type
  content_type = lookup(
    local.mime_types,
    lower(try(regex("\\.[^.]+$", each.value), "")),
    "application/octet-stream"
  )

  # (Optional) sensible caching: avoid caching HTML, cache-static everything else
  cache_control = contains(
    [".html", ".htm"],
    lower(try(regex("\\.[^.]+$", each.value), ""))
  ) ? "no-cache" : "public, max-age=31536000, immutable"
}

# 5) Output website endpoint
output "website_url" {
  value = aws_s3_bucket_website_configuration.static.website_endpoint
}