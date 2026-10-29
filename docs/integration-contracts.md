# Cloud Infrastructure Explorer — Integration Contracts

## 1. AWS Resource Contract

Every AWS resource discovered by our application must be converted into a consistent format before being stored in PostgreSQL.

### Resource Fields

| Field | Type | Description |
|---|---|---|
| provider | String | Cloud provider, initially "aws" |
| resource_id | String | Unique provider-assigned resource identifier |
| service | String | AWS service, initially "ec2" or "s3" |
| name | String | Human-readable resource name |
| region | String, nullable | AWS region when applicable |
| metadata | Hash | Additional non-secret resource properties |
| console_url | String, nullable | Direct AWS Console link when available |

### Example EC2 Resource

```ruby
{
  provider: "aws",
  resource_id: "i-0123456789abcdef0",
  service: "ec2",
  name: "production-server",
  region: "us-east-1",
  metadata: {
    instance_type: "t3.micro",
    state: "running"
  },
  console_url: "https://console.aws.amazon.com/ec2/"
}
```

### Integration Rules

1. AWS-specific API calls belong in the cloud provider adapter.
2. The adapter returns normalized resource records using this contract.
3. The application stores records in PostgreSQL.
4. The frontend reads stored records rather than calling AWS directly.
5. Failed scans must not delete previously discovered resources.
6. No AWS credentials or sensitive metadata may be stored in resource records.

### Initial Scope

- Provider: AWS
- Region: us-east-1
- Resource types: EC2 instances and S3 buckets
- Access: Read-only
- Scanning: Manually triggered



## 2. Cloud Provider Adapter Contract

The cloud provider adapter retrieves AWS resources and passes
normalized data to the Rails backend.

### Interface

Class: CloudProvider::Adapter

Method: list_resources(connection_context)

### Input

connection_context contains:
- provider: "aws"
- region: "us-east-1"
- resource_types: ["ec2", "s3"]

AWS credentials must be obtained securely from the environment,
not passed through or stored in application resource records.

### Output

The method returns:

- resources: Array of normalized resource records
- errors: Array of structured error records

Each resource follows the AWS Resource Contract in Section 1.

Each error includes:
- resource_type: The affected service
- code: A machine-readable error identifier
- message: A safe, human-readable explanation

### Rules

1. AWS SDK calls remain inside the provider adapter.
2. The adapter must not write directly to PostgreSQL.
3. The Rails backend handles persistence and scan status.
4. Errors must not be interpreted as an empty inventory.
5. Failed scans must preserve previously stored resources.


## 3. Component Ownership

### Cloud Integration Developer
- Implements CloudProvider::Adapter
- Handles AWS SDK requests and API errors
- Returns normalized resource records
- Does not write to PostgreSQL

### Application & Data Developer
- Implements Resource and Scan models
- Handles persistence and database migrations
- Implements ResourceNormalizer and inventory updates
- Preserves existing resources when scans fail

### Frontend & Product Developer
- Builds Rails views and user interactions
- Displays resources from the Rails backend
- Does not call AWS APIs directly

### Technical Lead & Integration Engineer
- Implements ScanCoordinator
- Connects the adapter to the persistence layer
- Reviews cross-component integration
- Coordinates integration testing

## 4. Sprint 1 Dashboard Contract

`GET /` and `GET /dashboard` render `DashboardController#index` using
`app/views/dashboard/index.html.erb`. The named route helper is `dashboard_path`.
The existing `/home/index` placeholder route remains available.

The controller reads stored AWS EC2 and S3 resources across **all environments**.
It does not initiate scans or call the cloud provider adapter. Resources are
ordered by name, then database ID, and their environments are preloaded.
Records with the same AWS identifier in different environments remain separate;
the prototype displays environment names to distinguish them.

### Variables available to the view

| Variable | Shape | Empty inventory |
|---|---|---|
| `@resources_by_service` | Hash from service string to an array of Resource objects | `{ "ec2" => [], "s3" => [] }` |
| `@resource_counts` | Hash from service string to its stored resource count | `{ "ec2" => 0, "s3" => 0 }` |

Both service keys always exist. Counts are derived from the same resource arrays
shown by the view. No seed data is required for the page to render successfully.

The initial template provides category anchors, counts, basic resource tables,
and empty-state messages. The frontend developer can iterate on presentation
using this interface. Category anchors are sections on the dashboard; separate
category listing routes are not part of Issue #11. Environment filtering,
pagination, authentication, and live scanning are separate work. This prototype
loads the small Sprint 1 inventory into memory and does not provide per-user
environment isolation.
