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

# ── SSM: Cognito social provider credentials ──────────────────────────────────

data "aws_ssm_parameter" "google_client_id" {
  name = "/${local.project}/${local.env}/google/client_id"
}

data "aws_ssm_parameter" "google_client_secret" {
  name            = "/${local.project}/${local.env}/google/client_secret"
  with_decryption = true
}


# ── Cognito: User Pool ────────────────────────────────────────────────────────

resource "aws_cognito_user_pool" "main" {
  name = "${local.project}-${local.env}"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_uppercase = false
    require_lowercase = false
    require_numbers   = false
    require_symbols   = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  schema {
    name                = "name"
    attribute_data_type = "String"
    mutable             = true
    required            = true
    string_attribute_constraints {
      min_length = 1
      max_length = 100
    }
  }

  tags = local.common_tags
}

# ── Cognito: Hosted UI domain ─────────────────────────────────────────────────

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${local.project}-${local.env}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# ── Cognito: Identity Providers ───────────────────────────────────────────────

resource "aws_cognito_identity_provider" "google" {
  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    client_id        = data.aws_ssm_parameter.google_client_id.value
    client_secret    = data.aws_ssm_parameter.google_client_secret.value
    authorize_scopes = "email profile openid"
  }

  attribute_mapping = {
    email    = "email"
    name     = "name"
    username = "sub"
  }
}


# ── Cognito: App Client (Next.js) ─────────────────────────────────────────────

resource "aws_cognito_user_pool_client" "nextjs" {
  name         = "${local.project}-nextjs-${local.env}"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  supported_identity_providers = [
    "COGNITO",
    "Google",
  ]

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  callback_urls = [
    "http://localhost:3000/api/auth/callback/cognito",
    "https://app.mamisactivas.com.ar/api/auth/callback/cognito",
  ]

  logout_urls = [
    "http://localhost:3000",
    "https://app.mamisactivas.com.ar",
  ]

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  depends_on = [
    aws_cognito_identity_provider.google,
  ]
}
