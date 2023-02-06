terraform {
  backend "s3" {
    bucket = "terraform-state-backup-vantruongsinh.myftp.org"
    key    = "terraform-state-prod.tfstate"
    region = "us-east-1"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.53.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_dynamodb_table" "dynamodb-table" {
  name           = "VisitorCount"
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "Date"
  attribute {
    name = "Date"
    type = "S"
  }

  tags = {
    Name        = "dynamodb-table"
    Environment = "production"
  }
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "lambda-dynamodb-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

data "aws_iam_policy" "AmazonDynamoDBFullAccess_policy" {
  name = "AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "attach_role" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = data.aws_iam_policy.AmazonDynamoDBFullAccess_policy.arn
}

resource "aws_lambda_function" "lambda_function" {
  # If the file is not in the current working directory you will need to include a
  # path.module in the filename.
  filename      = "lambda_function.zip"
  function_name = "get_visitor_count"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "lambda_function.lambda_handler"

  # The filebase64sha256() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the base64sha256() function and the file() function:
  # source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"
  source_code_hash = filebase64sha256("lambda_function.zip")

  runtime = "python3.9"

  environment {
    variables = {
      foo = "bar"
    }
  }
}

resource "aws_apigatewayv2_api" "apigateway" {
  name          = "visitor-count-api-gw"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET"]
  }
}


resource "aws_apigatewayv2_integration" "apigatewayv2_integration" {
  api_id           = aws_apigatewayv2_api.apigateway.id
  integration_type = "AWS_PROXY"

  connection_type        = "INTERNET"
  description            = "Lambda"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.lambda_function.invoke_arn
  passthrough_behavior   = "WHEN_NO_MATCH"
  payload_format_version = "2.0"
}


resource "aws_apigatewayv2_route" "example" {
  api_id    = aws_apigatewayv2_api.apigateway.id
  route_key = "GET /visitor-count"
  target    = "integrations/${aws_apigatewayv2_integration.apigatewayv2_integration.id}"


}

resource "aws_apigatewayv2_stage" "example" {
  api_id      = aws_apigatewayv2_api.apigateway.id
  name        = "$default"
  auto_deploy = true
}

output "apigateway_url" {
  value = "${aws_apigatewayv2_stage.example.invoke_url}visitor-count"

}