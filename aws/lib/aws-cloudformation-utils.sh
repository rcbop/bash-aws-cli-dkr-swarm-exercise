#!/bin/bash
#
# Requires colors.sh script
#
create_stack(){
    debug "$@"
    local STACK_NAME=$1; shift
    local STACK_FILE="${STACK_NAME//[0-9]/}.yaml";

    set -x
    aws cloudformation create-stack \
        --stack-name "${STACK_NAME}" \
        --tags "${AWS_TAGS}" \
        --template-body "file://./${BASEDIR}/aws/cloudformation/${STACK_FILE}" "$@"
    set +x
}

create_vpc_stack(){
    debug
    local STACK_NAME=$1
    local STACK_FILE=$2

    debug "file://./${BASEDIR}/aws/cloudformation/${STACK_FILE}"

    info "Creating cloudformation stack :: $STACK_NAME :: $STACK_FILE"
    
    create_stack "${STACK_NAME}"

    wait_stack_create_complete "${STACK_NAME}"
}

create_nat_gateway(){
    debug
    local STACK_NAME=$1
    local STACK_FILE=$2
    local PARENT_NAME=$3
    local SUBNET_ZONE=$4

    info "Creating cloudformation stack :: $STACK_NAME :: $STACK_FILE"
    debug "$3 :: $4 "

    create_stack "${STACK_NAME}" \
        --capabilities CAPABILITY_IAM \
        --parameters "ParameterKey=ParentVPCStack,ParameterValue=${PARENT_NAME}" "ParameterKey=SubnetZone,ParameterValue=${SUBNET_ZONE}"

    wait_stack_create_complete "${STACK_NAME}"
}

create_ssh_bastion(){
    debug
    local STACK_NAME=$1
    local STACK_FILE=$2
    local PARENT_NAME=$3
    local SSH_KEY_NAME=$4

    info "Creating cloudformation stack :: $STACK_NAME :: $STACK_FILE"
    debug "$3 :: $4"

    create_stack "${STACK_NAME}" \
        --capabilities CAPABILITY_IAM \
        --parameters "ParameterKey=ParentVPCStack,ParameterValue=${PARENT_NAME}" "ParameterKey=KeyName,ParameterValue=${SSH_KEY_NAME}"

    wait_stack_create_complete "${STACK_NAME}"
}

delete_cloudformation_stack(){
    debug
    local STACK_NAME=$1

    warning "Removing cloudformation stack :: ${STACK_NAME}"

    aws cloudformation delete-stack --stack-name "${STACK_NAME}" 

    wait_stack_delete_complete "${STACK_NAME}"
}

wait_stack_create_complete(){
    debug
    local STACK_NAME=$1

    warning "waiting for stack :: ${STACK_NAME} to be created"

    aws cloudformation wait stack-create-complete --stack-name "${STACK_NAME}" 2>/dev/null & pid=$!
    progress_indicator 300
}

wait_stack_delete_complete(){
    debug
    
    local STACK_NAME=$1

    warning "waiting for stack :: ${STACK_NAME} to be deleted"

    aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}" 2>/dev/null & pid=$!
    progress_indicator 300
}

cleanup_cloudformation_stacks(){
    debug
    delete_cloudformation_stack "${SSH_BASTION_STACK_NAME}" || warning "${SSH_BASTION_STACK_NAME} does not exists.. Skipping"
    delete_cloudformation_stack "${NAT_GATEWAY_STACK_NAME_B}" || warning "${NAT_GATEWAY_STACK_NAME_B} does not exists.. Skipping"
    delete_cloudformation_stack "${NAT_GATEWAY_STACK_NAME_A}" || warning "${NAT_GATEWAY_STACK_NAME_A} does not exists.. Skipping"
    delete_cloudformation_stack "${VPC_STACK_NAME}" || warning "${VPC_STACK_NAME} does not exists.. Skipping"
}