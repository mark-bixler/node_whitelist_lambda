terraform {}

# Configure the AWS Provider
provider "aws" {
  region     = "us-west-1"
}


// Create Role form Lambda To Run Under
resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda_test_mb"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

// Create Lambda For Doing work
resource "aws_lambda_function" "test_lambda" {
  filename         = "../../../_app/_app.zip"
  function_name    = "mb-securityGroup-whitelist-oktaGithub-lf"
  role             = "${aws_iam_role.iam_for_lambda.arn}"
  handler          = "exports.handler"
  source_code_hash = "${base64sha256(file("../../../_app/_app.zip"))}"
  runtime          = "nodejs8.10"

  environment {
    variables = {
      site = "okta"
    }
  }
}

# This is to optionally manage the CloudWatch Log Group for the Lambda Function.
# If skipping this resource configuration, also add "logs:CreateLogGroup" to the IAM policy below.
resource "aws_cloudwatch_log_group" "cloudwatch_test" {
  name              = "/aws/lambda/${aws_lambda_function.test_lambda.function_name}"
  retention_in_days = 14
}

# See also the following AWS managed policy: AWSLambdaBasicExecutionRole
resource "aws_iam_policy" "lambda_logging" {
  name        = "lambda_logging"
  path        = "/"
  description = "IAM policy for logging from a lambda"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = "${aws_iam_role.iam_for_lambda.name}"
  policy_arn = "${aws_iam_policy.lambda_logging.arn}"
}
