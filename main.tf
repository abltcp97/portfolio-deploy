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

resource "aws_dynamodb_table" "visitor_count" {
  name = "visitor-count"
  billing_mode = "PAY_PER_REQUEST"
  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
  Name = "visitor-count"
  Environment = "prod"
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

resource "aws_lambda_function" "visitor_count" {
  function_name = "visitor-counter-lambda"
  role = aws_iam_role.lambda_exec.arn
  handler = "lambda_function.lambda_handler"
  runtime = "python3.11"
  timeout = 5

  filename = "${path.module}/lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.visitor_count.name
    }
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_policy_attach]

}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role"

  assume_role_policy = jsonencode({
      Version = "2012-10-17",
      Statement = [{
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

#################### Exposing Lambda via API Gateway ####################################
resource "aws_apigatewayv2_api" "visitor_api" { # Creating HTTP API and will be our root public API. 
  name = "VisitorAPI"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" { #Linking Lambda function to API Gateway
  api_id = aws_apigatewayv2_api.visitor_api.id
  integration_type = "AWS_PROXY" #Send http request as is to Lambda
  integration_uri = aws_lambda_function.visitor_count.invoke_arn #Invoke ARN to tell API where to send request
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "visitor_route" { #Defines route and tells API to trigger lambda
  api_id = aws_apigatewayv2_api.visitor_api.id
  route_key = "GET /visits"
  target = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "api_stage" { # creating prod staging
  api_id = aws_apigatewayv2_api.visitor_api.id
  name = "$default"
  auto_deploy = true #allows changes to go live instantly
}

resource "aws_lambda_permission" "allow_apigw" { #grant permission to API to invoke lambda
  statement_id = "AllowAPIGatewayInvoke"
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_count.function_name
  principal = "apigateway.amazonaws.com"
  source_arn = "${aws_apigatewayv2_api.visitor_api.execution_arn}/*/*" #limit permission to only this arn
}
################################ END ################################################