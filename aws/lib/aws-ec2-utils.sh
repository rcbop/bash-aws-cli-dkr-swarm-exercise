#!/bin/bash
#
# Requires colors.sh script
#

enable_instance_termination_protection(){
  debug
  declare INSTANCES=$1
  aws ec2 modify-instance-attribute --instance-id "$INSTANCES" --disable-api-termination
}

iterate_and_enable_termination_protection(){
  debug
  local AWS_EC2_INSTANCES_IDS=$1

  IFS=' '
  for CURRENT_EC2_ID in ${AWS_EC2_INSTANCES_IDS} 
  do
    info "Enabling termination protection for $CURRENT_EC2_ID"
    enable_instance_termination_protection "${CURRENT_EC2_ID}"
  done
}

create_ec2_instance(){
  debug
  local NAME=$1
  local TYPE=$2

  info "Creating EC2 instance"

  CURRENT_EC2_ID=$(create_ec2_instance_subsh "$NAME" "$TYPE")
  [ -z "$CURRENT_EC2_ID" ] && fatal 'Unable to retrieve created instance id'
    
  info "Created EC2 ID :: $CURRENT_EC2_ID"
  create_tag "$CURRENT_EC2_ID" "$AWS_TAGS"
}

create_ec2_instance_subsh(){
  local NAME=$1
  local TYPE=$2
  set -x
  aws ec2 run-instances --image-id "${AWS_AMI_ID}" \
    --count 1 \
    --instance-type "${AWS_INSTANCE_TYPE}" \
    --key-name "${AWS_KEY_PAIR_NAME}" \
    --security-group-ids "${AWS_SECURITY_GROUP_ID}" \
    --subnet-id "${AWS_PRIVATE_SUBNET_ID}" \
    --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":${AWS_INSTANCE_SIZE}}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME}},{Key=Type,Value=${TYPE}}]" "ResourceType=volume,Tags=[{Key=Name,Value=${NAME}},{Key=Backup,Value=daily},{Key=Retention,Value=3}]" \
    --query "Instances[].InstanceId" --output text
  set +x
}

get_ec2_instance_id_sub(){
  declare INSTANCE_NAME=$1
  aws ec2 describe-instances --filter "Name=tag:Name,Values=${INSTANCE_NAME}" | jq -r '.[][].Instances[] | select(.State.Name == "running") | .InstanceId'
}

create_workers(){
  for CURRENT_WORKER in "${DOCKER_SWARM_WORKERS_ARRAY[@]}"
  do
    create_ec2_instance "${CURRENT_WORKER}" "worker"

    info "Worker created"
  done
}

wait_for_ec2_instances(){
  debug
  local EC2_IDS=$1
  # default timeout is 3 minutes
  local TIMEOUT_IN_SECONDS=${2:-180}

  aws ec2 wait instance-status-ok --instance-ids "${EC2_IDS}" 2>/dev/null & pid=$!
  progress_indicator ${TIMEOUT_IN_SECONDS}
}

create_manager(){
  debug
  create_ec2_instance "${DOCKER_SWARM_MANAGER_NAME}" "manager"
}

cleanup_workers(){
  warning "Removing workers instances"

  aws ec2 describe-instances --filters "Name=tag:$AWS_FILTER_TAG_KEY,Values=$AWS_FILTER_TAG_VALUE" "Name=tag:Type,Values=worker" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text | xargs -r -i aws ec2 terminate-instances --instance-ids {}
}

cleanup_managers(){
  warning "Removing managers instances"
  
  aws ec2 describe-instances --filters "Name=tag:$AWS_FILTER_TAG_KEY,Values=$AWS_FILTER_TAG_VALUE" "Name=tag:Type,Values=manager" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text | xargs -r -i aws ec2 terminate-instances --instance-ids {}
}

get_bastion_host_ip(){
  local BASTION_CLOUDFORMATION_STACK_NAME=$1
  aws ec2 describe-instances --filters "Name=tag:aws:cloudformation:stack-name,Values=${BASTION_CLOUDFORMATION_STACK_NAME}" \
    --query "Reservations[*][].Instances[*][].PublicIpAddress" --output text
}

get_bastion_host_id(){
  local BASTION_CLOUDFORMATION_STACK_NAME=$1
  aws ec2 describe-instances --filters "Name=tag:aws:cloudformation:stack-name,Values=${BASTION_CLOUDFORMATION_STACK_NAME}" \
    --query "Reservations[*][].Instances[*][].InstanceId" --output text
}
