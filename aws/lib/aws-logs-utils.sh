#!/bin/bash
#
# Requires colors.sh script
# Requires properties-utils.sh script
#
create_cloudwatch_log_group(){
  debug

  local AWS_LOG_GROUP_NAME=$1
  local AWS_LOG_GROUP_RETENTION=$2

  info "Checking if CloudWatch log group already exists :: group name :: $AWS_LOG_GROUP_NAME"
  AWS_LOG_GROUP_EXISTS=$(aws logs describe-log-groups | jq -r ".[][] | select(.logGroupName==\"$AWS_LOG_GROUP_NAME\")")

  if [ -z "$AWS_LOG_GROUP_EXISTS" ]; then
    info "Creating log group"
    eval aws logs create-log-group \
      --log-group-name "${AWS_LOG_GROUP_NAME}"

    [ $? != 0 ] && fatal "log group creation failed"

    set_property "AWS_LOG_GROUP_NAME" "$AWS_LOG_GROUP_NAME"

    info "Setting log group retention policy (in days): $AWS_LOG_GROUP_RETENTION "
    aws logs put-retention-policy \
      --log-group-name "${AWS_LOG_GROUP_NAME}" \
      --retention-in-days "${AWS_LOG_GROUP_RETENTION}"
  fi
}

get_curr_flow_log_id(){
  aws ec2 describe-flow-logs \
    --filter "Name=resource-id,Values=${AWS_VPC_ID}" | jq -r '.FlowLogs[0].FlowLogId | select (.!=null)' || echo ''
}

create_vpc_flow_logs(){
  debug
  
  # info "Getting flow logs"
  # AWS_FLOW_LOGS_ID=$(get_curr_flow_log_id)

  # if [ -z "$AWS_FLOW_LOGS_ID" ]; then

  info "Creating flow logs ID"
  aws ec2 create-flow-logs \
    --resource-type "VPC" \
    --resource-ids "${AWS_VPC_ID}" \
    --traffic-type "ALL" \
    --log-group-name "flow-logs-${AWS_VPC_ID}" \
    --deliver-logs-permission-arn "${AWS_FLOW_LOGS_IAM_ROLE_ARN}"

  AWS_FLOW_LOGS_ID=$(get_curr_flow_log_id)
    
  # fi
  info "Flow logs id : $AWS_FLOW_LOGS_ID"
  set_property "AWS_FLOW_LOGS_ID" "$AWS_FLOW_LOGS_ID"
}

cleanup_flow_logs(){
  debug

  warning "Cleaning up flow logs"
  
  get_curr_flow_log_id | xargs -r -i aws ec2 delete-flow-logs --flow-log-id {}

  aws logs describe-log-groups --query "logGroups[*].logGroupName" | jq -r ".[] | select(. | contains(\"$TAG_PREFIX\"))" | xargs -i -r aws logs delete-log-group --log-group-name "${AWS_LOG_GROUP_NAME}"
}