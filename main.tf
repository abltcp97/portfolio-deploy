terraform { # Storing terraform state in S3 bucket
  backend "s3" {
    bucket = "aalamillo-terraform-state" #stores it in this S3 Bucket
    key = "terraform.tfstate" #name of the state file
    region = "us-east-1" # Keep it in the region I selected
    dynamodb_table = "terraform-lock" # turns on state locking to prevnt conflicts
    encrypt = true #Encrypts the file at rest in S3
  }
}

provider "aws" { #selecting region
    region = "us-east-1"
}

resource "aws_s3_bucket" "terraform_state" { # creating s3 bucket
  bucket = "aalamillo-terraform-state"
}




resource "aws_s3_bucket_versioning" "versioning_enabled" { #enabling versioning
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" { #apply encryption to S3 bucket
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_dynamodb_table" "terraform_lock" { #Prevents another instance of terraform from happening at the same time
    name = "terraform-lock"
    billing_mode = "PAY_PER_REQUEST"
    hash_key = "LockID"

    attribute {
      name = "LockID"
      type = "S"
    }
  
}

resource "aws_cloudfront_origin_access_control" "oac" {
    name = "terraform-portfolio-oac"
    description = "OAC for secure s3 access"
    origin_access_control_origin_type = "s3"
    signing_behavior = "always"
    signing_protocol = "sigv4"
}

resource "aws_cloudfront_distribution" "portfolio" {
    origin {
      domain_name = aws_s3_bucket.terraform_state.bucket_regional_domain_name
      origin_id = "S3PortfolioOrigin"
      origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    }
    enabled = true
    default_root_object = "index.html" #ensures the main page loads

    aliases = ["portfolio.aalamillo.com"] # custom domain

    default_cache_behavior { #Tells cloudfront how to handle requests
      target_origin_id = "S3PortfolioOrigin"
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods = ["GET","HEAD"] # Only allowing Get and Head for security reasons
      cached_methods = ["GET","HEAD"]

      forwarded_values { # Preventing query and cookie forewarding to improve cache
        query_string = false 
        cookies {
          forward = "none"
        }
      }

      min_ttl =  3600 # 1 Hour Minimum
      default_ttl = 86400 # 1 day Default
      max_ttl = 604800 # 7 days max
    }

    restrictions {
      geo_restriction {
        restriction_type = "none"
      }
    }
    viewer_certificate {
      acm_certificate_arn = var.acm_certificate_arn #Allows us to have https
      ssl_support_method = "sni-only"
    }  
}

resource "aws_s3_bucket_policy" "allow_cloudfront" {
    bucket = aws_s3_bucket.terraform_state.id

    policy = jsonencode({
        Version = "2012-10-17",
        Statement = [
            {
                Effect = "Allow"
                Principal = {
                    Service = "cloudfront.amazonaws.com"
                },
                Action = "s3:GetObject",
                Resource = "arn:aws:s3:::aalamillo-terraform-state/*",
                Condition = {
                    StringEquals = {
                        "AWS:SourceArn" = aws_cloudfront_distribution.portfolio.arn
                    }
                }
            }
        ]
    })
  
}