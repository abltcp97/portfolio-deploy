resource "aws_s3_bucket" "portfolio_site" {
  bucket         = "portfolio-site-aalamillo"
  force_destroy  = true

  tags = {
    Name        = "Portfolio Static Site"
    Environment = "prod"
  }
}

resource "aws_s3_bucket_public_access_block" "portfolio_site" {
  bucket = aws_s3_bucket.portfolio_site.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}


resource "aws_s3_bucket_website_configuration" "portfolio_site" {
  bucket = aws_s3_bucket.portfolio_site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}

resource "aws_s3_bucket_policy" "allow_public_read" {
  bucket = aws_s3_bucket.portfolio_site.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "arn:aws:s3:::portfolio-site-aalamillo/*"
      }
    ]
  })
}
