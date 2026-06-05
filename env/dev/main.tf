terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.37"
    }
  }

  backend "s3" {
    bucket  = "terraform-state-700693144273-us-east-1-an"
    key     = "terraform/state/activas-training/env/dev/terraform.tfstate"
    region  = "us-east-1"
    profile = "jaguirre-aws-activas-training"
    encrypt = true
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "jaguirre-aws-activas-training"
}

locals {
  region  = "us-east-1"
  env     = "dev"
  project = "activas-training"

  common_tags = {
    project      = local.project
    environment  = local.env
    managed-by   = "terraform"
    source       = "activas-training-aws"
  }
}

data "aws_caller_identity" "current" {}


# ── S3: Website Media ────────────────────────────────────────────────

resource "aws_s3_bucket" "media" {
  bucket           = "activas-training-media-${data.aws_caller_identity.current.account_id}-${local.region}-an"
  bucket_namespace = "account-regional"
  tags             = local.common_tags
}

resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── CloudFront OAC ────────────────────────────────────────────────────────────

resource "aws_cloudfront_origin_access_control" "media" {
  name                              = "${local.project}-media-oac"
  description                       = "OAC for ${local.project} media bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ── CloudFront Distribution ───────────────────────────────────────────────────

resource "aws_cloudfront_distribution" "media" {
  comment     = "${local.project}-media-${local.env}"
  enabled     = true
  price_class = "PriceClass_All"
  tags        = local.common_tags

  origin {
    domain_name              = aws_s3_bucket.media.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.media.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.media.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.media.id}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    # AWS managed CachingOptimized policy
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["AR"]
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# ── Bucket policy: solo CloudFront puede leer ─────────────────────────────────

resource "aws_s3_bucket_policy" "media" {
  bucket = aws_s3_bucket.media.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.media.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.media.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.media]
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "media_bucket_name" {
  value = aws_s3_bucket.media.bucket
}

output "media_bucket_arn" {
  value = aws_s3_bucket.media.arn
}

output "cloudfront_oac_id" {
  value = aws_cloudfront_origin_access_control.media.id
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.media.id
}

output "cloudfront_distribution_arn" {
  value = aws_cloudfront_distribution.media.arn
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.media.domain_name
}
