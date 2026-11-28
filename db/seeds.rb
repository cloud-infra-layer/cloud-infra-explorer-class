# Fictional inventory for frontend development; no AWS requests or credentials.
# Reruns refresh these demo records without deleting other inventory.
# Keep the demo environment's name/provider/region stable to avoid creating
# another demo environment. Seed payloads follow the live ResourceSync allowlists.

demo_resources = [
  {
    service: "ec2",
    resource_id: "i-0123456789abcdef0",
    name: "Demo web server",
    metadata: {
      instance_type: "t3.micro",
      state: "running",
      cpu_utilization_pct: "18.40",
      estimated_monthly_cost_usd: "7.50"
    }
  },
  {
    service: "ec2",
    resource_id: "i-0123456789abcdef1",
    name: "Demo background worker",
    metadata: {
      instance_type: "t3.small",
      state: "running",
      cpu_utilization_pct: "42.10",
      estimated_monthly_cost_usd: "15.00"
    }
  },
  {
    service: "ec2",
    resource_id: "i-0123456789abcdef2",
    name: "Demo staging server",
    metadata: {
      instance_type: "t3.micro",
      state: "stopped",
      cpu_utilization_pct: "0.00",
      estimated_monthly_cost_usd: "7.50"
    }
  },
  {
    service: "s3",
    resource_id: "course-explorer-demo-assets",
    name: "Demo application assets",
    metadata: {
      creation_date: "2026-01-15T12:00:00Z",
      size_bytes: "104857600",
      object_count: "128"
    }
  },
  {
    service: "s3",
    resource_id: "course-explorer-demo-logs",
    name: "Demo application logs",
    metadata: {
      creation_date: "2026-02-01T08:30:00Z",
      size_bytes: "524288000",
      object_count: "2048"
    }
  },
  {
    service: "s3",
    resource_id: "course-explorer-demo-backups",
    name: "Demo backups",
    metadata: {
      creation_date: "2026-03-10T18:00:00Z",
      size_bytes: "2147483648",
      object_count: "64"
    }
  },
  {
    service: "rds",
    resource_id: "demo-app-db",
    name: "demo-app-db",
    metadata: {
      engine: "postgres",
      engine_version: "16.3",
      instance_class: "db.t4g.micro",
      status: "available",
      multi_az: "false",
      storage_gb: "20",
      estimated_monthly_cost_usd: "12.00"
    }
  },
  {
    service: "rds",
    resource_id: "demo-analytics-db",
    name: "demo-analytics-db",
    metadata: {
      engine: "mysql",
      engine_version: "8.0.39",
      instance_class: "db.t3.small",
      status: "available",
      multi_az: "true",
      storage_gb: "100",
      estimated_monthly_cost_usd: "30.00"
    }
  },
  {
    service: "bedrock",
    resource_id: "amazon.nova-lite-v1:0",
    name: "Nova Lite",
    metadata: {
      provider_name: "Amazon",
      lifecycle_status: "ACTIVE",
      input_modalities: "TEXT,IMAGE",
      estimated_monthly_cost_usd: "25.00"
    }
  },
  {
    service: "bedrock",
    resource_id: "anthropic.claude-3-haiku-20240307-v1:0",
    name: "Claude 3 Haiku",
    metadata: {
      provider_name: "Anthropic",
      lifecycle_status: "ACTIVE",
      input_modalities: "TEXT",
      estimated_monthly_cost_usd: "40.00"
    }
  }
]

# Monthly time series from Aug 2025 through Nov 2026 with realistic ups and downs.
demo_cost_amounts = {
  "Amazon Elastic Compute Cloud - Compute" => [
    18.40, 22.10, 19.75, 24.60, 21.30, 27.80, 25.40, 29.10,
    26.75, 31.20, 28.50, 33.80, 30.10, 35.40, 32.60, 36.25
  ],
  "Amazon Relational Database Service" => [
    34.00, 36.50, 33.20, 38.10, 40.00, 37.40, 42.80, 39.50,
    44.20, 41.10, 46.00, 43.25, 47.80, 45.00, 49.20, 46.50
  ],
  "Amazon Simple Storage Service" => [
    4.20, 4.80, 5.60, 5.10, 6.40, 5.90, 7.20, 6.70,
    8.10, 7.40, 8.80, 8.20, 9.50, 8.90, 10.10, 9.40
  ],
  "Amazon Bedrock" => [
    9.50, 14.20, 12.80, 18.40, 22.10, 19.60, 28.50, 34.20,
    31.00, 42.80, 48.50, 44.10, 55.20, 61.40, 58.00, 67.25
  ]
}

demo_cost_months = []
cursor = Date.new(2025, 8, 1)
month_index = 0
while cursor <= Date.new(2026, 11, 1)
  amounts = demo_cost_amounts.to_h do |service_code, values|
    [ service_code, format("%.2f", values.fetch(month_index)) ]
  end
  demo_cost_months << {
    period_start: cursor,
    period_end: cursor.end_of_month,
    amounts: amounts
  }
  cursor = cursor.next_month
  month_index += 1
end

Environment.transaction do
  environment = Environment.find_or_create_by!(
    name: "Course demo", provider: "aws", region: "us-east-1"
  )

  demo_resources.each do |attributes|
    identity = attributes.slice(:service, :resource_id).merge(provider: "aws")
    identity[:region] = "us-east-1" if Resource::REGION_SCOPED_SERVICES.include?(attributes[:service])

    resource = environment.resources.find_or_initialize_by(identity)
    console = case attributes[:service]
    when "ec2" then "https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1"
    when "s3" then "https://s3.console.aws.amazon.com/s3/buckets/#{attributes[:resource_id]}?region=us-east-1&tab=objects"
    when "rds" then "https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1#database:id=#{attributes[:resource_id]};is-cluster=false"
    when "bedrock" then "https://us-east-1.console.aws.amazon.com/bedrock/home?region=us-east-1#/models"
    end

    resource.assign_attributes(attributes.merge(
      provider: "aws",
      region: "us-east-1",
      console_url: console
    ))
    resource.save!
  end

  demo_cost_months.each do |month|
    month.fetch(:amounts).each do |service_code, amount|
      snapshot = environment.cost_snapshots.find_or_initialize_by(
        period_start: month.fetch(:period_start),
        period_end: month.fetch(:period_end),
        granularity: "MONTHLY",
        service_code: service_code
      )
      snapshot.assign_attributes(amount: amount, currency: "USD")
      snapshot.save!
    end
  end
end
