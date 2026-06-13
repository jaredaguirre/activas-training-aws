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

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_arn" {
  value = aws_cognito_user_pool.main.arn
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.nextjs.id
}

output "cognito_hosted_ui_domain" {
  value = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${local.region}.amazoncognito.com"
}

output "cognito_idp_redirect_uri" {
  description = "Registrar este URI en Google Cloud Console y Meta Developer"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${local.region}.amazoncognito.com/oauth2/idpresponse"
}
