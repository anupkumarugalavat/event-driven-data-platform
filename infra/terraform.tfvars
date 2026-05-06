aws_region = "us-east-1"
prefix     = "member-org-001"
valid_orgs = "ORG-123,ORG-456,UHD-DATA-01"

# FIX: container_image is now blank. The ecs.tf task definition uses the
# official public Python slim image and fetches processor.py from S3 at
# runtime, so no ECR image needs to be built or pushed for the demo.
# To use a private ECR image in production, set this to the full ECR URI
# and remove the command override in ecs.tf.
container_image = ""