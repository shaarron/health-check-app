variable "frontend-bucket" {
  type      = string
  sensitive = true
}

variable "aws-region" {
  type = string
}

data "aws_caller_identity" "current" {}

terraform {
  backend "s3" {}
}

provider "aws" {
  region = var.aws-region
}
# frontend S3 bucket
resource "aws_s3_bucket" "frontend-health-check" {
  bucket = var.frontend-bucket

  lifecycle {
    prevent_destroy = false
  }
  force_destroy = true
}

resource "aws_s3_bucket_website_configuration" "frontend-health-check" {
  bucket = aws_s3_bucket.frontend-health-check.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend-health-check-block" {
  bucket                  = aws_s3_bucket.frontend-health-check.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "frontend-bucket-policy" {
  bucket = aws_s3_bucket.frontend-health-check.id

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "cloudfront.amazonaws.com"
        },
        "Action" : "s3:GetObject",
        "Resource" : "arn:aws:s3:::${aws_s3_bucket.frontend-health-check.id}/*",
        "Condition" : {
          "StringEquals" : {
            "AWS:SourceArn" : "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.s3_distribution.id}"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Principal" : {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/terraform-user"
        },
        "Action" : "s3:*",
        "Resource" : [
          "arn:aws:s3:::${aws_s3_bucket.frontend-health-check.id}",
          "arn:aws:s3:::${aws_s3_bucket.frontend-health-check.id}/*"
        ]
      }

    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.frontend-health-check-block]
}

# CloudFront
resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "s3-oac"
  description                       = "OAC for S3 health-check web bucket access"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.frontend-health-check.bucket_regional_domain_name
    origin_id   = "frontend-health-check"

    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }

  enabled = true
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "frontend-health-check"
    viewer_protocol_policy = "allow-all"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  default_root_object = "index.html"

}


