#!/bin/bash
#
# Requires colors.sh script
# Requires properties-utils.sh script
#
create_role_for_flow_logs(){
    debug

    local AWS_VPC_FLOW_LOGS_ROLE=$1
    
    info "Creating IAM role for flow logs $AWS_VPC_FLOW_LOGS_ROLE"

    if [ -z "$(check_role_exists_subsh "$AWS_VPC_FLOW_LOGS_ROLE")" ]; then  

        info "Creating role based on role document :: $AWS_VPC_FLOW_LOGS_ROLE_FILE"  
        aws iam create-role \
            --role-name "${AWS_VPC_FLOW_LOGS_ROLE}" \
            --assume-role-policy-document "${AWS_VPC_FLOW_LOGS_ROLE_FILE}"

        set_property "AWS_VPC_FLOW_LOGS_ROLE" "$AWS_VPC_FLOW_LOGS_ROLE"

        info "Created :: $AWS_VPC_FLOW_LOGS_ROLE"
    else
        info "IAM Role already exists $AWS_VPC_FLOW_LOGS_ROLE"
    fi

    if [ -z "$(check_role_policy_subsh "$AWS_VPC_FLOW_LOGS_ROLE")" ]; then
        put_policy_in_role "$AWS_VPC_FLOW_LOGS_ROLE" "$AWS_VPC_FLOW_LOGS_POLICY" "$AWS_VPC_FLOW_LOGS_POLICY_FILE"
    fi
}

check_role_policy_subsh(){
    aws iam list-role-policies --role-name "$1" --query 'PolicyNames[*]' | jq '.[]'
}

put_policy_in_role(){
    debug
    aws iam put-role-policy --role-name "$1" --policy-name "$2" --policy-document "$3"
}

check_role_exists_subsh(){
    aws iam list-roles --query 'Roles[*].RoleName' | jq -r ".[] | select(.==\"$1\")"
}

get_role_arn_for_flow_logs(){
    debug

    local AWS_VPC_FLOW_LOGS_ROLE=$1

    info "Getting IAM role ARN for flow logs"

    AWS_FLOW_LOGS_IAM_ROLE_ARN=$(aws iam list-roles | jq -r ".Roles[] | select(.RoleName == \"$AWS_VPC_FLOW_LOGS_ROLE\") | .Arn")

    [ -z "${AWS_FLOW_LOGS_IAM_ROLE_ARN}" ] && fatal "ERROR in querying role arn"

    info "Query role ARN: $AWS_FLOW_LOGS_IAM_ROLE_ARN"
    set_property "AWS_FLOW_LOGS_IAM_ROLE_ARN" "${AWS_FLOW_LOGS_IAM_ROLE_ARN}"
}