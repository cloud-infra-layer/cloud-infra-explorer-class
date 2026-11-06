# AWS development setup and sandbox testing

Use the team sandbox account `821058455060` in `us-east-2` (Ohio). The adapter accepts other regions, but these profiles, policies, and test-resource instructions are specific to our sandbox.

| Profile | Purpose |
|---|---|
| `cloud-explorer-setup` | Browser login and administrator actions, including creating and removing test resources |
| `cloud-explorer-source` | Supplies temporary login credentials to the Ruby SDK |
| `cloud-explorer-dev` | Assumes `CloudExplorerDiscovery` for read-only discovery |

**Already configured?** Start with [Run discovery](#4-run-discovery), [Test a real S3 bucket](#5-test-a-real-s3-bucket), or [Test a real EC2 instance](#6-test-a-real-ec2-instance). Run commands from the repository root. Keep credentials and files under `~/.aws` out of Git and shared logs.

## 1. Install dependencies and sign in

Install the project's Ruby version, then:

```bash
bundle install
brew install awscli
aws --version
```

Browser login requires AWS CLI 2.32.0 or newer and an individual invitation to the team project.

```bash
aws login --profile cloud-explorer-setup --region us-east-2
aws configure set region us-east-2 --profile cloud-explorer-setup
aws sts get-caller-identity --profile cloud-explorer-setup
```

Choose the team project in the browser. Confirm that `Account` is `821058455060` and the ARN uses `AccountFullAccessRole` before administering resources. Repeat browser login when the session expires.

## 2. Configure local discovery profiles

Run once per developer:

```bash
aws configure set credential_process \
  'aws configure export-credentials --profile cloud-explorer-setup --format process' \
  --profile cloud-explorer-source
aws configure set region us-east-2 --profile cloud-explorer-source

aws configure set role_arn \
  arn:aws:iam::821058455060:role/CloudExplorerDiscovery \
  --profile cloud-explorer-dev
aws configure set source_profile cloud-explorer-source --profile cloud-explorer-dev
aws configure set region us-east-2 --profile cloud-explorer-dev
aws configure set duration_seconds 3600 --profile cloud-explorer-dev
```

The discovery role must exist before this profile can be used. Have an administrator complete step 3 if needed, then verify the profile:

```bash
aws sts get-caller-identity --profile cloud-explorer-dev
```

The ARN should contain `assumed-role/CloudExplorerDiscovery/` in account `821058455060`.

The credential-process bridge lets the pinned Ruby SDK assume the discovery role using temporary browser-login credentials. These commands save configuration, not permanent access keys. Do not run `export-credentials` separately or share its output. A deployed application needs its own workload identity.

## 3. Enable read-only permissions

**Administrator only.** Check whether the discovery role exists:

```bash
aws iam get-role --role-name CloudExplorerDiscovery \
  --profile cloud-explorer-setup --region us-east-2
```

If the response is `NoSuchEntity`, review the account-specific trust principal in `config/aws/discovery-trust-policy.json` and create the role. For other errors, resolve authentication or permissions before continuing. Skip creation if the role already exists.

```bash
aws iam create-role \
  --role-name CloudExplorerDiscovery \
  --assume-role-policy-document file://config/aws/discovery-trust-policy.json \
  --max-session-duration 3600 \
  --profile cloud-explorer-setup --region us-east-2
```

Apply both policies to the role. Repeating these commands replaces the named inline policies with the repository versions.

```bash
aws iam put-role-policy \
  --role-name CloudExplorerDiscovery \
  --policy-name EC2DiscoveryOhio \
  --policy-document file://config/aws/ec2-discovery-policy.json \
  --profile cloud-explorer-setup --region us-east-2

aws iam put-role-policy \
  --role-name CloudExplorerDiscovery \
  --policy-name S3DiscoveryOhio \
  --policy-document file://config/aws/s3-discovery-policy.json \
  --profile cloud-explorer-setup --region us-east-2
```

| Policy | Permission | Scope |
|---|---|---|
| `EC2DiscoveryOhio` | `ec2:DescribeInstances` | EC2 discovery in Ohio |
| `S3DiscoveryOhio` | `s3:ListAllMyBuckets` | Bucket-listing requests through the Ohio endpoint |

Both actions require `Resource: "*"`. S3's `aws:RequestedRegion` condition restricts the endpoint, not the bucket locations that the permission can enumerate. The adapter supplies a separate region filter and validates returned regions. The role has no object-reading, object-listing, creation, or deletion permissions; discovery does not require `HeadBucket` or `GetBucketLocation`.

## 4. Run discovery

Discover EC2 instances and S3 general-purpose buckets in Ohio:

```bash
AWS_PROFILE=cloud-explorer-dev AWS_REGION=us-east-2 bundle exec ruby script/verify_resources.rb
```

To test a single service:

```bash
AWS_PROFILE=cloud-explorer-dev AWS_REGION=us-east-2 bundle exec ruby script/verify_resources.rb --services ec2
AWS_PROFILE=cloud-explorer-dev AWS_REGION=us-east-2 bundle exec ruby script/verify_resources.rb --services s3
```

The script defaults to both services. Use `--services ec2`, `--services s3`, or `--services ec2,s3` to select services, and `--help` for usage. Unsupported service names or invalid arguments exit with status 2 before discovery.

The script prints JSON and exits with status 1 if any selected service reports an error, or 0 on success. It requires `AWS_REGION`, uses read-only credentials, and neither creates infrastructure nor saves records to PostgreSQL. Rails and a database are not needed.

- `"resources": [], "errors": []` means discovery succeeded but found no resources in the requested region.
- An error means discovery failed for the named service, even if its resource list is empty. Successful results from the other service remain available.
- S3 returns owned general-purpose buckets only. Missing bucket names or missing/mismatched regions cause the entire S3 result to fail. Directory buckets and cross-account bucket discovery are outside this implementation.

To call the adapter from Rails, start `AWS_PROFILE=cloud-explorer-dev bin/rails console`, then run:

```ruby
CloudProvider::Adapter.new.list_resources(
  provider: "aws", region: "us-east-2", resource_types: ["ec2", "s3"]
)
```

## 5. Test a real S3 bucket

An S3 resource is a **bucket**, rather than an instance. An empty bucket is enough to test discovery; do not upload objects. Use the setup profile for creation and cleanup and the discovery profile for verification.

### Create an empty sandbox bucket

Use the same terminal for creation and cleanup so `S3_TEST_BUCKET` remains available. First confirm the account:

```bash
aws sts get-caller-identity --profile cloud-explorer-setup
```

Proceed only if `Account` is `821058455060`. Generate a unique name and save the printed value for cleanup if your terminal closes:

```bash
S3_TEST_BUCKET="cie-test-821058455060-$(ruby -rsecurerandom -e 'puts SecureRandom.hex(8)')"
echo "$S3_TEST_BUCKET"

aws s3api create-bucket \
  --bucket "$S3_TEST_BUCKET" \
  --create-bucket-configuration LocationConstraint=us-east-2 \
  --profile cloud-explorer-setup --region us-east-2
```

Continue only after creation succeeds. A name collision requires a new name; do not treat an existing bucket as one you just created. New buckets block public access by default. Explicitly retain that configuration:

```bash
aws s3api put-public-access-block \
  --bucket "${S3_TEST_BUCKET:?Set the test bucket name first}" \
  --expected-bucket-owner 821058455060 \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
  --profile cloud-explorer-setup --region us-east-2
```

These setup operations require `s3:CreateBucket` and `s3:PutBucketPublicAccessBlock`; cleanup requires `s3:DeleteBucket`. Keep those permissions on the setup identity, not the discovery role. If a command fails after creation, the bucket may still exist. Inspect it and either finish configuring it for reuse or delete it below.

### Verify discovery

```bash
AWS_PROFILE=cloud-explorer-dev AWS_REGION=us-east-2 bundle exec ruby script/verify_resources.rb
```

Find the resource whose `resource_id` matches the printed bucket name. Confirm:

| Field | Expected value |
|---|---|
| `provider` | `aws` |
| `service` | `s3` |
| `resource_id`, `name` | Your `S3_TEST_BUCKET` value |
| `region` | `us-east-2` |
| `metadata` | `{}` |
| `console_url` | An S3 console link containing your bucket name and `region=us-east-2` |
| Top-level `errors` | `[]` for a fully successful EC2 and S3 scan |

Other existing resources may also appear. No EC2 instance is required: successful empty EC2 discovery is valid.

### Keep the bucket for repeated tests

You can keep the empty, private bucket for development and demos. S3 has no stopped state: the bucket remains discoverable until deleted. Leave public access blocked and avoid uploading objects unless a test requires them. S3 charges depend on storage, requests, and other enabled features, so retaining an empty bucket does not mean all operations are free.

Save its name, account, region, and responsible team member in your team's resource inventory. To reuse it in a new terminal, restore its name and run discovery without repeating creation:

```bash
S3_TEST_BUCKET="REPLACE_WITH_SAVED_BUCKET_NAME"
AWS_PROFILE=cloud-explorer-dev AWS_REGION=us-east-2 bundle exec ruby script/verify_resources.rb
```

### Delete the bucket when no longer needed

If you are not keeping the bucket for reuse, delete it after testing, including after failed verification. For a shared bucket, confirm the team has finished using it. If you reopened the terminal, set `S3_TEST_BUCKET` to the exact saved name first.

```bash
aws s3api delete-bucket \
  --bucket "${S3_TEST_BUCKET:?Set the test bucket name first}" \
  --expected-bucket-owner 821058455060 \
  --profile cloud-explorer-setup --region us-east-2
```

A successful deletion returns no output and exit status 0. `BucketNotEmpty` means someone added data; inspect it before proceeding. Do not use recursive or forced deletion. This workflow intentionally creates an empty bucket.

Rerun discovery and confirm the test bucket is absent with no S3 error.

## 6. Test a real EC2 instance

The helper creates one `t3.micro` in the sandbox. Cleanup is a separate command, not automatic. You can retain the instance for repeated tests and stop it between sessions. Compute and EBS usage consume credits or incur charges. Run this manually, never in CI.

### Create and verify an instance

List existing subnets and choose an available sandbox subnet:

```bash
aws ec2 describe-subnets \
  --profile cloud-explorer-setup --region us-east-2 \
  --query 'Subnets[].{Subnet:SubnetId,VPC:VpcId,AZ:AvailabilityZone,State:State}' \
  --output table
```

Replace `subnet-REPLACE_ME`, then create and verify:

```bash
TEST_RUN="ec2-$(date -u +%Y%m%d%H%M%S)"
bash script/ec2_test_instance.sh create "$TEST_RUN" subnet-REPLACE_ME

AWS_PROFILE=cloud-explorer-dev AWS_REGION=us-east-2 bundle exec ruby script/verify_resources.rb --services ec2
```

Confirm the printed instance ID appears with name `cloud-explorer-test-<run-id>`, type `t3.micro`, state `running`, region `us-east-2`, and no errors. EC2 is eventually consistent; retry shortly afterward if a newly created instance is not yet listed.

### Keep, stop, and restart the instance

Save the helper's run ID and instance ID, account, region, and responsible team member in your team's resource inventory. Keep the helper's `ManagedBy` and `TestRun` tags so cleanup can find the resources later. Reuse the existing instance instead of creating another for each test.

Set the instance ID to the value printed by the helper or returned by discovery. Stop it when you do not need it running:

```bash
EC2_TEST_INSTANCE_ID="i-REPLACE_ME"

aws ec2 stop-instances \
  --instance-ids "${EC2_TEST_INSTANCE_ID:?Set the test instance ID first}" \
  --profile cloud-explorer-setup --region us-east-2
aws ec2 wait instance-stopped \
  --instance-ids "${EC2_TEST_INSTANCE_ID:?Set the test instance ID first}" \
  --profile cloud-explorer-setup --region us-east-2
```

A stopped instance remains discoverable with state `stopped`, so it is sufficient for inventory testing. Stopping ends instance compute charges, but retained EBS storage still incurs charges. The instance and its storage are not deleted.

When a test or demo needs state `running`, restore `EC2_TEST_INSTANCE_ID` if necessary, then start the same instance:

```bash
aws ec2 start-instances \
  --instance-ids "${EC2_TEST_INSTANCE_ID:?Set the test instance ID first}" \
  --profile cloud-explorer-setup --region us-east-2
aws ec2 wait instance-running \
  --instance-ids "${EC2_TEST_INSTANCE_ID:?Set the test instance ID first}" \
  --profile cloud-explorer-setup --region us-east-2

AWS_PROFILE=cloud-explorer-dev AWS_REGION=us-east-2 bundle exec ruby script/verify_resources.rb --services ec2
```

Stop/start operations require `ec2:StopInstances` and `ec2:StartInstances`; the wait commands require `ec2:DescribeInstances`. Use the setup identity, not the read-only discovery role.

### Delete the instance when no longer needed

If you are not keeping the instance for reuse, clean it up after testing, including after failed verification. For a shared instance, confirm the team has finished using it. If you reopened the terminal, restore `TEST_RUN` to the original run ID, not a new timestamp. Cleanup works for running or stopped instances and permanently terminates them:

```bash
bash script/ec2_test_instance.sh cleanup "${TEST_RUN:?Set the original test run ID first}"
```

The helper checks the account, uses exact test-run tags, and refuses ambiguous matches. It creates an encrypted 8 GiB root volume and an isolated security group, with no public IP, SSH key, instance role, or inbound/outbound rules. It requires IMDSv2. The setup identity needs SSM access to the public AMI parameter and EC2 permissions for the helper's describe, create, tag, and delete operations.

Cleanup waits for termination and removes the test security group. The root volume and network interface are configured for deletion on termination. Existing VPCs and subnets are preserved. If no subnet exists, coordinate with the team before creating shared networking.

There is no scheduled cleanup. Agree on who will remove retained resources when testing or the project ends. Rerun cleanup if it fails and inspect remaining tagged resources. Use a fresh run ID only when creating a new instance.

## 7. Automated tests and troubleshooting

These tests use mocked AWS responses and a fake CLI; they do not access AWS or require PostgreSQL:

```bash
bundle exec ruby test/services/cloud_provider/adapter_test.rb
bundle exec ruby test/services/cloud_provider/s3_adapter_test.rb
bundle exec ruby test/scripts/ec2_test_instance_test.rb
bundle exec ruby test/scripts/verify_resources_test.rb
```

They also run with `bin/rails test` and in CI. Never add live AWS credentials to CI for these tests.

| Symptom | What to check |
|---|---|
| Expired login | Repeat the browser login in step 1; restart a long-running Rails process afterward. |
| `credentials_unavailable` | Confirm all three profiles exist and `aws` is on PATH. Remove stale `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_SESSION_TOKEN` variables if they override the profile. |
| `invalid_context` | Supply `AWS_REGION=us-east-2` when running a verification script. |
| S3 `aws_api_error` | Confirm the administrator applied `S3DiscoveryOhio`; allow IAM changes time to propagate. |
| Other `aws_api_error` | Check the role identity, requested region, and IAM or organization restrictions. |
| `invalid_resource` | AWS returned missing identity or inconsistent region data. Retry; do not treat it as an empty inventory. |
| `network_error` | Check connectivity and retry. |
| Test resource missing | Confirm its account and region, and check `errors` before interpreting an empty result. |
| Cleanup fails | Retain the bucket name or EC2 run ID and inspect the exact test resource. Do not assume it was removed. |

## References

- [AWS CLI browser login](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)
- [Ruby SDK authentication](https://docs.aws.amazon.com/sdk-for-ruby/v3/developer-guide/credentials.html)
- [S3 ListBuckets and region filtering](https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListBuckets.html)
- [Create an S3 bucket](https://docs.aws.amazon.com/cli/latest/reference/s3api/create-bucket.html)
- [Delete an empty S3 bucket](https://docs.aws.amazon.com/cli/latest/reference/s3api/delete-bucket.html)
- [Stop and start EC2 instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Stop_Start.html)
- [S3 pricing](https://aws.amazon.com/s3/pricing/)
- [EC2 discovery permissions](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonec2.html)
