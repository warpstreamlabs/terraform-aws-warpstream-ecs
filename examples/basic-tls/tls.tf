// Create self-signed certificates
// In a real deployment you will want to use real certificates signed by a certificate authority
resource "tls_private_key" "warpstream" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_self_signed_cert" "warpstream" {
  private_key_pem = tls_private_key.warpstream.private_key_pem

  // See documentation here for a proper certificate setup
  // https://docs.warpstream.com/warpstream/byoc/advanced-agent-deployment-options/protect-data-in-motion-with-tls-encryption#configure-tls-encryption-for-a-warpstream-cluster
  // In this example this certificate uses an invalid hostname that does not match the WarpStream containers
  // so communication will not work without skipping TLS verification on clients.
  dns_names = ["example.com"]
  subject {
    common_name  = "example.com"
    organization = "ACME Examples, Inc"
  }

  validity_period_hours = 30 * 24

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

// Setup bucket to install the TLS certificates into
resource "aws_s3_bucket" "tls_bucket" {
  bucket_prefix = "${local.name}-tls-"
}

resource "aws_s3_bucket_public_access_block" "tls_bucket" {
  bucket = aws_s3_bucket.tls_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "tls_bucket" {
  bucket = aws_s3_bucket.tls_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "tls_bucket" {
  depends_on = [aws_s3_bucket_ownership_controls.tls_bucket]

  bucket = aws_s3_bucket.tls_bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_lifecycle_configuration" "tls_bucket" {
  bucket = aws_s3_bucket.tls_bucket.id

  # Automatically cancel all multi-part uploads after 7d so we don't accumulate an infinite
  # number of partial uploads.
  rule {
    id     = "7d multi-part"
    status = "Enabled"
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

// Upload the certificates into the bucket
resource "aws_s3_object" "warpstream_certificate_key" {
  bucket  = aws_s3_bucket.tls_bucket.bucket
  key     = "tls.key"
  content = tls_private_key.warpstream.private_key_pem
}

resource "aws_s3_object" "warpstream_certificate_certificate" {
  bucket  = aws_s3_bucket.tls_bucket.bucket
  key     = "tls.crt"
  content = tls_self_signed_cert.warpstream.cert_pem
}

data "aws_iam_policy_document" "ec2_ecs_task_s3_tls" {
  statement {
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetObject",
    ]

    resources = [
      "arn:aws:s3:::${aws_s3_bucket.tls_bucket.bucket}",
      "arn:aws:s3:::${aws_s3_bucket.tls_bucket.bucket}/*"
    ]
  }
}
