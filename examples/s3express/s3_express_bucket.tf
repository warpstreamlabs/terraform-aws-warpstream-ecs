# Creating the bucket, access controls and lifecycle
locals {
  # S3 Express may not be available in every zone in a region. This
  # is fine though because we don't get billed for inter-zone networking
  # between EC2 and S3 Express buckets. You can see the list of available
  # zone IDs here: https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-express-Endpoints.html
  s3_express_zones_ids = ["use1-az4", "use1-az5", "use1-az6"]
}

# Random id to prevent bucket name clashes if more then one person runs this example
resource "random_id" "s3_express_bucket" {
  byte_length = 11
}

resource "aws_s3_directory_bucket" "s3_express_buckets" {
  count = length(local.s3_express_zones_ids)

  # AZ has to be encoded in this exact format, see docs:
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_directory_bucket
  bucket          = "${local.name}-${random_id.s3_express_bucket.hex}--${local.s3_express_zones_ids[count.index]}--x-s3"
  data_redundancy = "SingleAvailabilityZone"
  type            = "Directory"

  location {
    name = local.s3_express_zones_ids[count.index]
    type = "AvailabilityZone"
  }
}

# Currently doesn't work on aws_s3_directory_bucket
# │ Error: Provider produced inconsistent final plan
# │
# │ When expanding the plan for aws_s3_bucket_lifecycle_configuration.bucket[1] to include new values learned so far during apply, provider
# │ "registry.terraform.io/hashicorp/aws" produced an invalid new value for .transition_default_minimum_object_size: was known, but now unknown.
# │
# │ This is a bug in the provider, which should be reported in the provider's own issue tracker.
# resource "aws_s3_bucket_lifecycle_configuration" "bucket" {
#   count = length(local.s3_express_zones_ids)

#   bucket = aws_s3_directory_bucket.s3_express_buckets[count.index].bucket

#   # Automatically cancel all multi-part uploads after 7d so we don't accumulate an infinite
#   # number of partial uploads.
#   rule {
#     id     = "7d multi-part"
#     status = "Enabled"
#     abort_incomplete_multipart_upload {
#       days_after_initiation = 7
#     }
#   }

#   # No other lifecycle policy. The WarpStream Agent will automatically clean up and
#   # deleted expired files.
# }



