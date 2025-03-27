output "aws_cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.portfolio.id
}

output "visitor_api_endpoint" {
  value = "${aws_apigatewayv2_api.visitor_api.api_endpoint}/visits"
}

output "visitor_api_base_url" {
  value = aws_apigatewayv2_api.visitor_api.api_endpoint
}