#!/usr/bin/env bash
# Opt-in live test fixture. This script creates billable resources; never run in CI.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bash script/ec2_test_instance.sh create RUN_ID SUBNET_ID
  bash script/ec2_test_instance.sh cleanup RUN_ID

RUN_ID: unique lowercase name, 3-40 characters (letters, numbers, hyphens).
Uses cloud-explorer-setup in sandbox account 821058455060, us-east-2 only.
Creation launches one t3.micro and an encrypted 8 GiB root volume. Clean up promptly.
Cleanup terminates only the instance and deletes the security group tagged for RUN_ID.
USAGE
}

fail() { echo "Error: $*" >&2; exit 1; }
if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
action=${1:-}
run_id=${2:-}
[[ $action == create || $action == cleanup ]] || { usage; exit 1; }
[[ $run_id =~ ^[a-z0-9][a-z0-9-]{2,39}$ ]] || fail "Provide a unique RUN_ID (see --help)."
if [[ $action == create ]]; then
  [[ $# == 3 && $3 =~ ^subnet-[0-9a-f]+$ ]] || fail "Create requires a subnet ID."
else
  [[ $# == 2 ]] || fail "Cleanup requires only RUN_ID."
fi

command -v aws >/dev/null || fail "Install AWS CLI v2 first."
aws_cli() { aws --profile cloud-explorer-setup --region us-east-2 --no-cli-pager "$@"; }
account=$(aws_cli sts get-caller-identity --query Account --output text)
[[ $account == 821058455060 ]] || fail "Wrong AWS account; no resources changed."

# Tags allow recovery after interruption without relying on a local state file.
filters=("Name=tag:ManagedBy,Values=cloud-explorer-live-test" "Name=tag:TestRun,Values=$run_id")
tags="[{Key=ManagedBy,Value=cloud-explorer-live-test},{Key=TestRun,Value=$run_id},{Key=Name,Value=cloud-explorer-test-$run_id}]"
instance_id=$(aws_cli ec2 describe-instances --filters "${filters[@]}" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
group_id=$(aws_cli ec2 describe-security-groups --filters "${filters[@]}" \
  --query 'SecurityGroups[].GroupId' --output text)

# Refuse ambiguous matches rather than terminating more than one resource.
[[ -z $instance_id || $instance_id =~ ^i-[0-9a-f]+$ ]] || fail "Multiple or invalid instance matches; inspect tags manually."
[[ -z $group_id || $group_id =~ ^sg-[0-9a-f]+$ ]] || fail "Multiple or invalid security group matches; inspect tags manually."

trap 'echo "Command failed. Resources may remain. Recover with: bash script/ec2_test_instance.sh cleanup $run_id" >&2' ERR

if [[ $action == cleanup ]]; then
  if [[ -n $instance_id ]]; then
    echo "Terminating $instance_id for test run $run_id."
    aws_cli ec2 terminate-instances --instance-ids "$instance_id" --output json
    aws_cli ec2 wait instance-terminated --instance-ids "$instance_id"
  fi
  if [[ -n $group_id ]]; then
    # Instance termination can precede network-interface release.
    for attempt in 1 2 3 4 5 6; do
      if result=$(aws_cli ec2 delete-security-group --group-id "$group_id" 2>&1); then
        break
      fi
      if [[ $result == *InvalidGroup.NotFound* ]]; then break; fi
      if [[ $result != *DependencyViolation* || $attempt == 6 ]]; then
        fail "Could not delete $group_id: $result. Rerun cleanup after checking its dependencies."
      fi
      sleep 5
    done
  fi
  echo "Cleanup completed for $run_id. The launch root volume is configured for deletion on termination."
  exit 0
fi

if [[ -n $instance_id ]]; then
  echo "Test run $run_id already has instance $instance_id; no new resources created."
  echo "Use a new RUN_ID for a new test, even after termination."
  exit 0
fi

subnet_id=$3
vpc_id=$(aws_cli ec2 describe-subnets --subnet-ids "$subnet_id" --query 'Subnets[0].VpcId' --output text)
[[ $vpc_id =~ ^vpc-[0-9a-f]+$ ]] || fail "Subnet did not resolve to a VPC in Ohio."
image_id=$(aws_cli ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text)
root_device=$(aws_cli ec2 describe-images --image-ids "$image_id" --owners amazon \
  --query 'Images[0].RootDeviceName' --output text)
[[ $root_device == /dev/xvda || $root_device == /dev/sda1 ]] || fail "Unexpected Amazon Linux root device."

if [[ -z $group_id ]]; then
  group_id=$(aws_cli ec2 create-security-group --group-name "cloud-explorer-test-$run_id" \
    --description "Isolated EC2 discovery test $run_id" --vpc-id "$vpc_id" \
    --tag-specifications "ResourceType=security-group,Tags=$tags" --query GroupId --output text)
else
  group_vpc=$(aws_cli ec2 describe-security-groups --group-ids "$group_id" --query 'SecurityGroups[0].VpcId' --output text)
  [[ $group_vpc == "$vpc_id" ]] || fail "Existing test group belongs to another VPC; use the original subnet or clean up."
fi

# No inbound rules are added; remove default outbound rules as well.
ingress=$(aws_cli ec2 describe-security-groups --group-ids "$group_id" \
  --query 'SecurityGroups[0].IpPermissions' --output json)
[[ $ingress == '[]' ]] || fail "Test group has unexpected inbound rules; inspect it before launching."
egress=$(aws_cli ec2 describe-security-groups --group-ids "$group_id" \
  --query 'SecurityGroups[0].IpPermissionsEgress' --output json)
if [[ $egress != '[]' ]]; then
  aws_cli ec2 revoke-security-group-egress --group-id "$group_id" --ip-permissions "$egress" --output json
fi

echo "Launching one t3.micro in $subnet_id. Compute and EBS usage consume credits or incur charges."
instance_id=$(aws_cli ec2 run-instances --image-id "$image_id" --instance-type t3.micro --count 1 \
  --client-token "cloud-explorer-$run_id" \
  --network-interfaces "DeviceIndex=0,SubnetId=$subnet_id,Groups=[$group_id],AssociatePublicIpAddress=false,DeleteOnTermination=true" \
  --block-device-mappings "DeviceName=$root_device,Ebs={VolumeSize=8,VolumeType=gp3,Encrypted=true,DeleteOnTermination=true}" \
  --metadata-options HttpTokens=required,HttpPutResponseHopLimit=1 \
  --credit-specification CpuCredits=standard \
  --tag-specifications "ResourceType=instance,Tags=$tags" "ResourceType=volume,Tags=$tags" \
  --query 'Instances[0].InstanceId' --output text)
echo "Instance: $instance_id"
echo "Cleanup: bash script/ec2_test_instance.sh cleanup $run_id"
aws_cli ec2 wait instance-running --instance-ids "$instance_id"
echo "Ready. Run: AWS_PROFILE=cloud-explorer-dev bundle exec ruby script/verify_ec2.rb"
