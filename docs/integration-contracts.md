# Cloud Infrastructure Explorer: Integration Contracts

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
  region: "us-east-2",
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
- Region: one region per scan, supplied by the selected environment; the team sandbox uses `us-east-2` (US East, Ohio)
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
- region: "us-east-2"
- resource_types: ["ec2", "s3"]

Request `["ec2"]`, `["s3"]`, or `["ec2", "s3"]`. Both services require the selected environment's explicit region.
The adapter accepts symbol or string hash keys; values use the strings shown above.
The region must be an AWS region code supplied by the selected environment, such as `us-east-2` or `eu-west-1`. The adapter passes it to the SDK and includes it in returned resources. Region format validation does not establish service availability or account access; AWS permissions and region availability determine whether discovery succeeds. Scans do not enumerate other regions automatically.

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

### Adapter behavior

- `CloudProvider::Adapter` is implemented in `app/services/cloud_provider/adapter.rb`.
- EC2 discovery reads all response pages and reservations. It uses the `Name` tag,
  falling back to the instance ID when the tag is missing or blank.
- Console links are generated for regions recognized by the installed SDK in the commercial AWS partition. Other regions return `console_url: nil` rather than an incorrect link.
- Discovery does not filter by sandbox account, test tags, instance ID, instance type, or state. Credentials determine the account being scanned.
- Metadata includes only `instance_type` and `state`; arbitrary tags and raw AWS
  responses are not copied into metadata.
- A successful empty discovery returns `{ resources: [], errors: [] }`.
- If any page fails, all results for that service are discarded and a safe structured error is returned. An error is not proof that resources disappeared.
- Unsupported types produce `unsupported_resource_type`. Successful results from either service are preserved when the other service fails. The backend must not treat the overall scan as a complete successful inventory or delete missing resources based on it.
- Expected failures use `credentials_unavailable`, `aws_api_error`, `network_error`, or `invalid_resource`, with the affected service as `resource_type`. Raw exception messages are not returned. Invalid input uses `invalid_context` and `resource_type: "connection"`.
- This adapter performs no database writes and does not implement scan status,
  reconciliation, or historical snapshots.


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



---

# 5. Sprint 2 Integration Contracts

## Objective

Sprint 2 connects AWS discovery to persistent inventory and the Rails frontend.

The intended workflow is:

User → Rails Controller → ScanCoordinator → CloudProvider::Adapter
                                      ↓
                                ResourceSync
                                      ↓
                                  PostgreSQL
                                      ↓
                                   Dashboard

All cloud access remains read-only.

## 5.1 Component Ownership

### Cloud Integration — GS

Owns:
- `app/services/cloud_provider/`
- AWS SDK interactions
- EC2 and S3 discovery
- Provider-specific error handling
- Mocked AWS API tests
- AWS setup documentation

The adapter never writes to PostgreSQL.

### Application & Data — Sam

Owns:
- `app/models/scan.rb`
- `app/models/resource.rb`
- Database migrations
- `app/services/resource_sync.rb`
- Scan persistence and resource upserts
- Database and service tests

Persistence services never call AWS APIs.

### Frontend & Product — Ian

Owns:
- Rails views and frontend components
- Manual scan controls
- Scan status and error presentation
- Resource listings and dashboard updates
- Frontend and integration tests

Frontend views never call AWS APIs directly.

### Technical Direction & Integration — Brayden

Owns:
- `app/services/scan_coordinator.rb`
- Scan orchestration
- `app/controllers/scans_controller.rb`
- Integration contracts
- Cross-component integration tests
- CI verification and deployment

## 5.2 Cloud Provider Adapter

Existing interface:

CloudProvider::Adapter#list_resources(connection_context)

Input:

{
  provider: "aws",
  region: "us-east-2",
  resource_types: ["ec2", "s3"]
}

Output:

{
  resources: [...],
  errors: [...]
}

Each resource must follow the normalized resource contract in Section 1.

Each error must contain:
- resource_type
- code
- message

EC2 and S3 discovery are supported. Each request requires one explicit region, including S3-only requests. Missing or malformed regions fail before any AWS client is created. There is no implicit account-wide scan or fallback to the sandbox region.

EC2 calls the selected region's `DescribeInstances` endpoint with pagination. S3 calls paginated `ListBuckets` using `bucket_region` equal to the selected region and a matching regional client. S3 returns account-owned general-purpose buckets only; directory buckets and buckets owned by another account are out of scope.

S3 resource mapping uses the bucket name for both `resource_id` and `name`, `BucketRegion` for `region`, and an empty metadata hash. No object contents, tags, or raw SDK responses are retrieved. The list response provides the region; no `HeadBucket` or `GetBucketLocation` calls are made. Console links are included for recognized commercial AWS regions and otherwise remain null.

Both services require a nonblank resource identifier. S3 also requires a returned region matching the requested region. Missing or inconsistent required fields produce `invalid_resource`; the adapter does not guess a region, silently skip records, or return a bucket with `region: nil`. Optional fields do not cause service failure.

Discovery is all-or-nothing within each service: a failed page or invalid required field discards that service's results. The other service is still attempted, and its successful results are retained, including valid empty results. An error identifies the failed service so the coordinator can distinguish partial from failed scans. SDK retries are bounded, and neither service performs database writes or deletion.

Successful discovery of zero resources is valid.

Failed discovery must never be interpreted as proof that existing resources
have been deleted.

## 5.3 Resource Persistence

New service:

ResourceSync

Proposed interface:

ResourceSync.new(environment: environment).call(resources: resources)

Returns:

{
  created: 0,
  updated: 0
}

Responsibilities:
- Validate normalized resource records.
- Associate resources with the selected Environment.
- Insert newly discovered resources.
- Update previously discovered resources.
- Avoid duplicates on repeated scans.
- Preserve resources belonging to other environments.
- Never store AWS credentials or secrets.

Existing resource identity rules remain unchanged:

EC2:
environment_id + provider + region + resource_id

S3:
environment_id + provider + resource_id

Sprint 2 synchronization is additive/update-based.

Deleting resources absent from a scan is out of scope.

A failed database write must report an error rather than silently
claiming synchronization succeeded.

## 5.4 Scan Model

New model: Scan

A Scan belongs to an Environment.

Required fields:
- environment_id
- status
- resource_types (JSON array)
- discovered_count
- created_count
- updated_count
- errors (JSON array)
- started_at
- completed_at

Allowed status values:
- running
- completed
- partial
- failed

Definitions:

running:
The scan has started but has not finished.

completed:
All requested resource types were discovered and synchronized
successfully, including valid empty results.

partial:
At least one requested resource type succeeded, but another failed.

failed:
Discovery or persistence failed without a fully successful result.

The Scan record must preserve safe error information.

Never save credentials or raw AWS exception messages.

## 5.5 ScanCoordinator

Existing constructor:

ScanCoordinator.new(environment: environment, adapter: adapter)

Sprint 2 extends the coordinator with a persistence service while
retaining injectable dependencies for testing.

Responsibilities:
1. Accept an Environment and requested resource types.
2. Create a Scan record with status running.
3. Call CloudProvider::Adapter#list_resources.
4. Separate successful discovery results from failed resource types.
5. Pass only successfully discovered resource types to ResourceSync.
6. Record resource counts and structured errors.
7. Mark the scan completed, partial, or failed.
8. Return the Scan result.

No AWS-specific SDK logic belongs in ScanCoordinator.

A failed or unsupported service must never cause existing resources
to be deleted.

Database persistence errors must result in a failed or partial scan
rather than a false success.

## 5.6 Manual Scan Endpoint

Proposed route:

POST /environments/:environment_id/scans

Controller:

ScansController#create

The controller:
- Resolves the selected Environment.
- Validates requested resource types.
- Invokes ScanCoordinator.
- Redirects to the dashboard after the synchronous Sprint 2 scan.
- Displays success, partial-success, or failure feedback.

The initial implementation is synchronous.

Background jobs, polling, and real-time progress updates are not
required for Sprint 2.

Ian can implement the form and status presentation using controller
stubs until the backend is connected.

Security requirement:

The scan endpoint must not be publicly usable without access control.

Production scan triggering must remain disabled until an appropriate
authorization mechanism is established.

## 5.7 Frontend Behavior

The dashboard should display:
- EC2 and S3 resource counts
- A manual scan action
- The latest scan status for the selected environment
- Safe error messages when discovery fails
- Updated stored resources after successful synchronization

The dashboard and resource listings continue reading from PostgreSQL.

They must not call CloudProvider::Adapter directly.

During a scan, the frontend must not falsely indicate that inventory
is up to date.

## 5.8 Acceptance Criteria

Sprint 2 is complete when:

1. EC2 and S3 discovery follow the normalized adapter contract.
2. A manual scan can be initiated through the authorized application UI.
3. ScanCoordinator orchestrates discovery and persistence.
4. Scan results and status are recorded in PostgreSQL.
5. New resources are created and existing resources are updated.
6. Repeated scans do not create duplicates.
7. Failed or partial scans preserve existing inventory.
8. The dashboard displays updated stored resources.
9. Automated tests pass without requiring real AWS credentials.
10. GitHub CI passes and the integrated application is deployed.

A live AWS sandbox test should be performed using approved
read-only credentials when the end-to-end integration is ready.
