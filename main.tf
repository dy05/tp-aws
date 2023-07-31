variable "authDataRegion" {
    type = string
    default = "us-east-1"
}

variable "authDataAccessKey" {
    type = string
    default = ""
}

variable "authDataSecretKey" {
    type = string
    default = ""
}

provider "aws" {
    region = var.authDataRegion
    access_key = var.authDataAccessKey
    secret_key = var.authDataSecretKey
}

resource "aws_dynamodb_table" "jobTable" {
    name         = "JOBS"
    billing_mode = "PAY_PER_REQUEST"
    hash_key = "id"

    attribute {
        name = "id"
        type = "N"
    }

    stream_enabled = true
    stream_view_type = "NEW_IMAGE"

    point_in_time_recovery {
        enabled = true
    }

    tags = {
        Name        = "myapp"
        Environment = "dev"
    }
}

resource "aws_dynamodb_table" "addToDynamoTable" {
    name         = "addToDynamos"
    billing_mode = "PAY_PER_REQUEST"
    hash_key = "id"

    attribute {
        name = "id"
        type = "N"
    }

    point_in_time_recovery {
        enabled = true
    }

    tags = {
        Name        = "myapp"
        Environment = "dev"
    }
}

resource "aws_s3_bucket" "addToS3" {
    bucket = "myterras3appbucket"

    tags = {
        Name        = "myapp"
        Environment = "dev"
    }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_encryption" {
    bucket = aws_s3_bucket.addToS3.bucket
    rule {
        apply_server_side_encryption_by_default {
            sse_algorithm     = "AES256"
        }
    }
}

resource "aws_iam_role" "lambda_role" {
    name = "add_job_lambda_role"

    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Effect = "Allow"
                Principal = {
                    Service = "lambda.amazonaws.com"
                }
            },
            {
                Effect = "Allow",
                Action = ["dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:DescribeStream", "dynamodb:ListStreams"],
                "Resource": ["*"]
            },
            {
                Effect: "Allow",
                Action: [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                "Resource": ["*"]
            }
        ]
    })
}

resource "aws_iam_policy" "dynamodb_policy" {
    name        = "DynamoDBPolicy"
    description = "Permissions to write and read DynamoDB table"
    policy = jsonencode({
        Version = "2012-10-17",
        Statement = [
            {
                Effect = "Allow",
                Action = ["dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:DescribeStream", "dynamodb:ListStreams"],
                "Resource": ["*"]
            }
        ]
    })
}

resource "aws_iam_role_policy_attachment" "dynamodb_attachment" {
    role       = aws_iam_role.lambda_role.name
    policy_arn = aws_iam_policy.dynamodb_policy.arn
}

resource "aws_lambda_function" "addTerraJob" {
    filename = "./addjob.zip"
    function_name = "addjob"
    #    role = "arn:aws:iam::897458684608:role/service-role/lambdaNode-role-nvxsl0kz"
    role = aws_iam_role.lambda_role.arn
    handler = "addjob.handler"
    runtime = "nodejs14.x"
    source_code_hash = filebase64sha256("./addjob.zip")

    tags = {
        Name        = "myapp"
        Environment = "dev"
    }

    environment  {
        variables = {
            TABLE_NAME = "JOBS"
        }
    }
}

resource "aws_lambda_function" "eventDbLambda" {
    filename        = "./db.zip"
    function_name   = "eventDbTerra"
    role            = "arn:aws:iam::897458684608:role/service-role/lambdaNode-role-nvxsl0kz"
    handler         = "eventDbTerra.handler"
    runtime         = "nodejs14.x"
    source_code_hash = filebase64sha256("./db.zip")

    tags = {
        Name        = "myapp"
        Environment = "dev"
    }
    environment {
        variables = {
            TABLE_NAME = "JOBS"
        }
    }
}

resource "aws_apigatewayv2_api" "addTerraJobApi" {
    name          = "addTerraJobApi"
    protocol_type = "HTTP"
    cors_configuration {
        allow_origins = ["*"]
        allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    }
}

resource "aws_apigatewayv2_stage" "defaultJobStage" {
    api_id    = aws_apigatewayv2_api.addTerraJobApi.id
    depends_on = [
        aws_apigatewayv2_route.apiTerraRoute
    ]
    name      = "default"
    auto_deploy = true
}

resource "aws_apigatewayv2_integration" "addTerraJobApiIntegration" {
    api_id             = aws_apigatewayv2_api.addTerraJobApi.id
    integration_type   = "AWS_PROXY"
    integration_uri    = aws_lambda_function.addTerraJob.invoke_arn
    integration_method = "POST"
}

resource "aws_apigatewayv2_route" "apiTerraRoute" {
    api_id    = aws_apigatewayv2_api.addTerraJobApi.id
    route_key = "ANY /{proxy+}"
    target    = "integrations/${aws_apigatewayv2_integration.addTerraJobApiIntegration.id}"
}

resource "aws_lambda_event_source_mapping" "event_source_mapping" {
    event_source_arn  = aws_dynamodb_table.jobTable.stream_arn
    function_name     = aws_lambda_function.addTerraJob.arn
    starting_position = "LATEST"
}

resource "aws_lambda_permission" "apiJobPermission" {
    statement_id  = "AllowAPIGatewayInvoke"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.addTerraJob.arn
    principal     = "apigateway.amazonaws.com"
    source_arn    = aws_apigatewayv2_api.addTerraJobApi.execution_arn
}

output "api_endpoint" {
    value = aws_apigatewayv2_api.addTerraJobApi.api_endpoint
}

#resource "aws_apigatewayv2_api" "eventDbApi" {
#    name          = "eventDbApi"
#    protocol_type = "HTTP"
#    cors_configuration {
#        allow_origins = ["*"]
#        allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
#    }
#}
#
#resource "aws_apigatewayv2_integration" "addTerraEventEBApiIntegration" {
#    api_id             = aws_apigatewayv2_api.eventDbApi.id
#    integration_type   = "AWS_PROXY"
#    integration_uri    = aws_lambda_function.eventDbLambda.invoke_arn
#    integration_method = "POST"
#}

resource "aws_cloudwatch_event_rule" "add_job_rule" {
    name        = "example_cloudwatch_rule"
    description = "Example CloudWatch Events Rule"

    tags = {
        Name        = "myapp"
        Environment = "dev"
    }

    # Define the event pattern to match specific events or event sources
    event_pattern = <<PATTERN
{
  "source": ["aws.ec2"],
  "detail-type": ["EC2 Instance State-change Notification"],
  "detail": {
    "state": ["pending", "running", "shutting-down"]
  }
}
PATTERN
}

resource "aws_cloudwatch_event_rule" "event_db_event_rule" {
    name        = "event_db_event_rule"
    description = "Rule for triggering process_job Lambda function"
    event_pattern = <<EOF
{
  "source": ["aws.dynamodb"],
  "detail-type": ["Dynamo DB Table Event"],
  "detail": {
    "eventSourceARN": ["${aws_dynamodb_table.jobTable.arn}"],
    "eventName": ["INSERT", "MODIFY"]
  }
}
EOF

    tags = {
        Name        = "myapp"
        Environment = "dev"
    }
}

resource "aws_cloudwatch_event_target" "add_job_event_target" {
    rule      = aws_cloudwatch_event_rule.add_job_rule.name
    arn       = aws_lambda_function.addTerraJob.arn
    target_id = "process_job_target"
}

resource "aws_cloudwatch_event_target" "event_db_event_target" {
    rule      = aws_cloudwatch_event_rule.event_db_event_rule.name
    arn       = aws_lambda_function.eventDbLambda.arn
    target_id = "process_job_target"
}

resource "aws_lambda_permission" "add_job_permission" {
    statement_id  = "AllowExecutionFromCloudWatch"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.addTerraJob.arn
    principal     = "events.amazonaws.com"
    source_arn    = aws_cloudwatch_event_rule.add_job_rule.arn
}

resource "aws_lambda_permission" "avent_db_permission" {
    statement_id  = "AllowExecutionFromCloudWatch"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.eventDbLambda.arn
    principal     = "events.amazonaws.com"
    source_arn    = aws_cloudwatch_event_rule.event_db_event_rule.arn
}

#resource "aws_apigatewayv2_api" "lambdaApi" {
#    #    role          = "arn:aws:iam::897458684608:role/service-role/lambdaNode-role-nvxsl0kz"
##    role = aws_iam_role.lambdaTerraRole.arn
##    handler = "lambdaApi.handler"
##    runtime = "nodejs14.x"
##    source_code_hash = "lambdaNode.zip"

##    api_id    = ""
##    route_key = "/"
#    name      = "lambdaApi"
#    protocol_type = "HTTP"

#    tags = {
#        Name        = "myapp"
#        Environment = "dev"
#    }
#}

#resource "aws_apigatewayv2_integration" "addJobLambdaIntegration" {
#    api_id               = aws_apigatewayv2_api.lambdaApi.id
#    integration_type     = "AWS_PROXY"
#    integration_uri      = aws_lambda_function.addTerraJob.invoke_arn
#    integration_method   = "POST"
#    payload_format_version = "2.0"
#}

#resource "aws_apigatewayv2_integration" "eventDbLambdaIntegration" {
#    api_id               = aws_apigatewayv2_api.lambdaApi.id
#    integration_type     = "AWS_PROXY"
#    integration_uri      = aws_lambda_function.eventDbLambda.invoke_arn
#    integration_method   = "POST"
#    payload_format_version = "2.0"
#}

#resource "aws_lambda_event_source_mapping" "dynamodb_mapping" {
#    event_source_arn = aws_dynamodb_table.jobTable.stream_arn
#    function_name    = aws_lambda_function.eventDbLambda.function_name
#    starting_position = "LATEST"
#}

#resource "aws_apigatewayv2_route" "addJobLambdaRoute" {
#    api_id    = aws_apigatewayv2_api.lambdaApi.id
#    route_key = "GET /addjob"
#    target    = "integrations/${aws_apigatewayv2_integration.addJobLambdaIntegration.id}"
#}

#resource "aws_apigatewayv2_route" "eventDbLambdaRoute" {
#    api_id    = aws_apigatewayv2_api.lambdaApi.id
#    route_key = "GET /selectdb"
#    target    = "integrations/${aws_apigatewayv2_integration.eventDbLambdaIntegration.id}"
#}
