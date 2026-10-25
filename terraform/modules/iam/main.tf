data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.name}-app-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

data "aws_iam_policy_document" "app" {
  statement {
    sid       = "ReadDbSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.secret_arn]
  }
  statement {
    sid       = "PullReleases"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.releases_bucket}/releases/*"]
  }
  statement {
    sid       = "WriteUploads"
    actions   = ["s3:PutObject"]
    resources = ["${var.app_bucket_arn}/uploads/*"]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "app-least-privilege"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

# Session Manager access instead of SSH (no port 22 open)
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name}-app-profile"
  role = aws_iam_role.app.name
}
