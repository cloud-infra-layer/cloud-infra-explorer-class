# Fictional inventory for frontend development; no AWS requests or credentials.
# Reruns refresh these demo records without deleting other inventory.
# Keep the demo environment's name/provider/region stable to avoid creating
# another demo environment. See the README's sample-data limitations.

demo_resources = [
  {
    service: "ec2",
    resource_id: "i-0123456789abcdef0",
    name: "Demo web server",
    metadata: { instance_type: "t3.micro", state: "running" }
  },
  {
    service: "ec2",
    resource_id: "i-0123456789abcdef1",
    name: "Demo background worker",
    metadata: { instance_type: "t3.small", state: "running" }
  },
  {
    service: "ec2",
    resource_id: "i-0123456789abcdef2",
    name: "Demo staging server",
    metadata: { instance_type: "t3.micro", state: "stopped" }
  },
  {
    service: "s3",
    resource_id: "course-explorer-demo-assets",
    name: "Demo application assets",
    metadata: { purpose: "static assets" }
  },
  {
    service: "s3",
    resource_id: "course-explorer-demo-logs",
    name: "Demo application logs",
    metadata: { purpose: "application logs" }
  },
  {
    service: "s3",
    resource_id: "course-explorer-demo-backups",
    name: "Demo backups",
    metadata: { purpose: "backups" }
  }
]

Environment.transaction do
  environment = Environment.find_or_create_by!(
    name: "Course demo", provider: "aws", region: "us-east-1"
  )

  demo_resources.each do |attributes|
    identity = attributes.slice(:service, :resource_id).merge(provider: "aws")
    # EC2 identity includes region; S3 identity does not.
    identity[:region] = "us-east-1" if attributes[:service] == "ec2"

    resource = environment.resources.find_or_initialize_by(identity)
    resource.assign_attributes(attributes.merge(
      provider: "aws",
      region: "us-east-1",
      console_url: attributes[:service] == "ec2" ? "https://console.aws.amazon.com/ec2/" : "https://s3.console.aws.amazon.com/s3/"
    ))
    resource.save!
  end
end
