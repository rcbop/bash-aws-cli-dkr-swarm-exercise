#!/usr/bin/env bash
#/ Description:
#/      CREATE DOCKER SWARM AWS EC2 CLUSTER
#/ Usage:
#/ Options:
#/ Examples:
#/      DEBUG=true ./create-ec2-swarm-cluster.sh  (Enable debug messages)
#/      NO_COLORS=true ./create-ec2-swarm-cluster.sh (Disable colors)
#/ --------------------------------------------------------------------------------
#/ Author: Rogério Castelo Branco Peixoto
#/ --------------------------------------------------------------------------------
usage() { grep '^#/' "$0" | cut -c4- ; exit 0 ; }
expr "$*" : ".*--help" > /dev/null && usage

BASEDIR=$(dirname "$0")

##################################################################
# SETUP LOGS
##################################################################

DATE=$(date "+%Y%m%dT%H%M%S")

mkdir -p "${BASEDIR}/logs"
LOG_FILE=${LOG_FILE:-"${BASEDIR}/logs/${0}-$DATE.log"}
touch "${LOG_FILE}"

##################################################################
# SOURCING LIB FUNCTIONS
##################################################################

# shellcheck source=utils/colors.sh
source "${BASEDIR}"/utils/colors.sh
# shellcheck source=utils/check-dependencies.sh
source "${BASEDIR}"/utils/check-dependencies.sh
# shellcheck source=utils/properties-utils.sh
source "${BASEDIR}"/utils/properties-utils.sh
# shellcheck source=aws/lib/aws-security-group-utils.sh
source "${BASEDIR}"/aws/lib/aws-security-utils.sh
# shellcheck source=aws/lib/aws-vpc-network-utils.sh
source "${BASEDIR}"/aws/lib/aws-vpc-network-utils.sh
# shellcheck source=aws/lib/aws-iam-policy-utils.sh
source "${BASEDIR}"/aws/lib/aws-iam-policy-utils.sh
# shellcheck source=aws/lib/aws-route53-utils.sh
source "${BASEDIR}"/aws/lib/aws-route53-utils.sh
# shellcheck source=aws/lib/aws-elb-utils.sh
source "${BASEDIR}"/aws/lib/aws-elb-utils.sh
# shellcheck source=aws/lib/aws-logs-utils.sh
source "${BASEDIR}"/aws/lib/aws-logs-utils.sh
# shellcheck source=aws/lib/aws-acm-utils.sh
source "${BASEDIR}"/aws/lib/aws-acm-utils.sh
# shellcheck source=aws/lib/aws-cleanup-utils.sh
source "${BASEDIR}"/aws/lib/aws-cleanup-utils.sh
# shellcheck source=./aws/lib/aws-ec2-utils.sh
source "${BASEDIR}"/aws/lib/aws-ec2-utils.sh
# shellcheck source=./aws/lib/aws-cloudformation-utils.sh
source "${BASEDIR}"/aws/lib/aws-cloudformation-utils.sh
# shellcheck source=ansible/lib/ansible-utils.sh
source "${BASEDIR}"/ansible/lib/ansible-utils.sh

##################################################################
# CHECK SCRIPT DEPENDENCIES
##################################################################

if is_no_colors; then
  unset_colors
else
  set_colors
fi

separator
bump_step "CHECKING SCRIPT DEPENDENCIES"

check_current_script_dependencies

##################################################################
# LOADING INPUT PARAMS
##################################################################

separator
bump_step "LOADING INPUT PARAMS"

# load properties from file into environment variable
PROPERTIES_FILE="${BASEDIR}/aws-variables.properties"
check_input_file_exists "${PROPERTIES_FILE}"
convert_properties_crlf_to_unix "${PROPERTIES_FILE}"
# shellcheck source=aws-variables.properties
set -o allexport; source "${PROPERTIES_FILE}"; set +o allexport

# load passwords from file into environment variables if present
PASSWORDS_FILE="${BASEDIR}/password.properties"
if [ -f "$PASSWORDS_FILE" ]; then
  info "Passwords file found..."
  convert_properties_crlf_to_unix "${PASSWORDS_FILE}"
  # shellcheck source=password.properties
  set -o allexport; source "${PASSWORDS_FILE}"; set +o allexport
else
  warning "Passwords file not defined... using environment variables"
fi


##################################################################
# CREATE OUTPUT FILE
##################################################################

separator
bump_step "CREATING OUTPUT FILE"

# properties output file
PROPERTIES_FILE_OUT="${BASEDIR}/aws-variables-out.properties"
touch "${PROPERTIES_FILE_OUT}"
# # shellcheck source=./aws-variables-out.properties
# set -o allexport; source "${PROPERTIES_FILE_OUT}"; set +o allexport

##################################################################
# CHECK MANDATORY VARIABLES
##################################################################

separator
bump_step "CHECKING MANDATORY VARIABLES"

# CLI PARAMS
: ${AWS_KEY_ID:?}
: ${AWS_SECRET_KEY:?}

# SSH KEYS
: ${AWS_KEY_PAIR_NAME:?}
: ${AWS_KEY_PAIR_PATH:?}

# TAG INFORMATION
: ${TAG_PREFIX:?}
: ${PROJECT_OWNER:?}

##################################################################
# CONFIGURE AWS CLI
##################################################################

separator
bump_step "CONFIGURING AWS CLI"

AWS_PROFILE_GEN=$(uuidgen)

aws configure set aws_access_key_id "${AWS_KEY_ID}" --profile "${AWS_PROFILE_GEN}"
aws configure set aws_secret_access_key "${AWS_SECRET_KEY}" --profile "${AWS_PROFILE_GEN}"
aws configure set output 'json' --profile "${AWS_PROFILE_GEN}"
aws configure set region "${AWS_REGION}" --profile "${AWS_PROFILE_GEN}"

export AWS_PROFILE="${AWS_PROFILE_GEN}"
export AWS_REGION="${AWS_REGION}"

##################################################################
# SETTING DEFAULT PROPERTIES
##################################################################

separator
bump_step "SETTING DEFAULT PROPERTIES VALUES"

#ami-b70554c8 // us-east-1
#ami-e0ba5c83 // us-west-1
#ami-a9d09ed1 // us-west-2
AWS_AMI_ID=${AWS_AMI_ID:-"ami-e0ba5c83"}

VPC_STACK_NAME="dkr-swarm-vpc-twoazs"
VPC_STACK_FILE="dkr-swarm-vpc-twoazs.yaml"
NAT_GATEWAY_STACK_NAME_A="dkr-swarm-vpc-nat-gateway1"
NAT_GATEWAY_STACK_NAME_B="dkr-swarm-vpc-nat-gateway2"
NAT_GATEWAY_STACK_FILE="dkr-swarm-vpc-nat-gateway.yaml"
SSH_BASTION_STACK_NAME="dkr-swarm-vpc-ssh-bastion1"
SSH_BASTION_STACK_FILE="dkr-swarm-vpc-ssh-bastion.yaml"

KEY_PAIR_CREATED_FILE=${KEY_PAIR_CREATED_FILE:-'ec2-swarm-cluster.pem'}
KEY_PAIR_CREATED_NAME=${KEY_PAIR_CREATED_NAME:-'ec2-swarm-cluster'}

DOCKER_MACHINE_DRIVER=${DOCKER_MACHINE_DRIVER:-'amazonec2'}

ENVIRONMENT=${ENVIRONMENT:-'development'}
APPLICATION=${APPLICATION:-'dkr-cluster'}
COST_CENTER=${COST_CENTER:-'default'}

AWS_TAGS=${AWS_TAGS:-"[{\"Key\":\"Project\",\"Value\":\"${TAG_PREFIX}\"},{\"Key\":\"Cost\",\"Value\":\"${COST_CENTER}\"},{\"Key\":\"Application\",\"Value\":\"${APPLICATION}\"},{\"Key\":\"Environment\",\"Value\":\"${ENVIRONMENT}\"},{\"Key\":\"Owner\",\"Value\":\"${PROJECT_OWNER}\"},{\"Key\":\"Date\",\"Value\":\"${DATE}\"}]"}
# info "Current project tags"
# set -x
# echo "${AWS_TAGS}" | jq
# set +x

VPC_NAME="${TAG_PREFIX}-${ENVIRONMENT}-vpc"

AWS_SUBNET_ID=${AWS_SUBNET_ID:-''}
AWS_AV_ZONE=${AWS_AV_ZONE:-'c'}
AWS_INSTANCE_TYPE=${AWS_INSTANCE_TYPE:-'t2.medium'}
AWS_INSTANCE_SIZE=${AWS_INSTANCE_SIZE:-'50'}
AWS_SECGROUP_NAME=${AWS_SECGROUP_NAME:-"$TAG_PREFIX-swarm-cluster-sec-group"}
AWS_CERTIFICATE_DOMAIN=${AWS_CERTIFICATE_DOMAIN:-"*.swarmclusterdomain.net"}

AWS_FILTER_TAG_KEY="Project"
AWS_FILTER_TAG_VALUE="${TAG_PREFIX}"

AWS_REGISTRY_ID=${AWS_REGISTRY_ID:-'728118514760'}
AWS_CLI_USER=${AWS_CLI_USER:-'root'}

# DNS info
AWS_ROUTE_53_DOMAIN=${AWS_ROUTE_53_DOMAIN:-'swarmclusterdomain.net'}
AWS_ROUTE_53_SUBDOMAIN=${AWS_ROUTE_53_SUBDOMAIN:-"$TAG_PREFIX-sub-domain"}

AWS_EC2_AMI_DEFAULT_USER=${AWS_EC2_AMI_DEFAULT_USER:-'ubuntu'}

# swarm nodes
NODE_PREFIX="$TAG_PREFIX-$ENVIRONMENT"
DOCKER_SWARM_MANAGER_NAME=${DOCKER_SWARM_MANAGER_NAME:-"$NODE_PREFIX-manager01"}

declare -a DOCKER_SWARM_WORKERS_ARRAY=("$NODE_PREFIX-worker01" "$NODE_PREFIX-worker02")
declare -a DOCKER_SWARM_PORTS_TO_OPEN_ARRAY=("tcp:2377" "tcp:7946" "udp:7946" "tcp:4789" "udp:4789")

AWS_VPC_FLOW_LOGS_ROLE=${AWS_VPC_FLOW_LOGS_ROLE:-"$TAG_PREFIX-vpc-flow-logs-role"}
AWS_VPC_FLOW_LOGS_POLICY=${AWS_VPC_FLOW_LOGS_POLICY:-"$TAG_PREFIX-flow-logs-policy"}
AWS_VPC_FLOW_LOGS_POLICY_FILE=${AWS_VPC_FLOW_LOGS_POLICY_FILE:-'file://aws/vpc-flow-logs-policy.json'}
AWS_VPC_FLOW_LOGS_ROLE_FILE=${AWS_VPC_FLOW_LOGS_ROLE_FILE:-'file://aws/vpc-flow-logs-role.json'}

AWS_LOG_GROUP_NAME=${AWS_LOG_GROUP_NAME:-"$TAG_PREFIX-vpc-log-group"}
AWS_LOG_GROUP_RETENTION=${AWS_LOG_GROUP_RETENTION:-"180"}

AWS_ELB_NAME="$TAG_PREFIX-classic-elb"

# NETWORK CIDR
AWS_VPC_IPV4_CIDR=${AWS_VPC_IPV4_CIDR:-'10.0.0.0/16'}
AWS_PUB_SUB_CIDR=${AWS_PUB_SUB_CIDR:-"10.0.1.0/24"}
AWS_PVT_SUB_CIDR=${AWS_PVT_SUB_CIDR:-"10.0.0.0/24"}

POST_SWARM_SETUP=${POST_SWARM_SETUP:-false}

AWS_PROVISIONING_COMPLETE=${AWS_PROVISIONING_COMPLETE:-false}

declare -a AWS_ELB_MAPPING=("HTTP/80:80" "HTTPS/443:443")

##################################################################
# END OF SETTING DEFAULT PROPERTIES
##################################################################

IFS=' '

wait_for(){
  debug

  local TIME_TO_WAIT=$1

  warning "Waiting $TIME_TO_WAIT seconds"
  sleep ${TIME_TO_WAIT}
}

set_phase_complete(){
  log "${MAG}[PHASE]   $1       COMPLETE${NC}"
  export CURRENT_PHASE=$1
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  SECONDS=0

  trap 'err_cleanup "$BASH_COMMAND"' ERR
  trap 'exit_cleanup' EXIT

  set -eE

  export CURRENT_PHASE=0

  separator "${YEL}"
  separator "${YEL}"
  separator "${YEL}"
  info
  bump_step "STARTING TO CREATE EC2 SWARM CLUSTER"
  info
  separator "${YEL}"
  separator "${YEL}"
  separator "${YEL}"

  if [[ "$AWS_PROVISIONING_COMPLETE" != "true" ]]; then

    bump_step "CREATING VPC :: CLOUDFORMATION"

    create_vpc_stack "${VPC_STACK_NAME}" "${VPC_STACK_FILE}"

    ELAPSED="Elapsed: $((SECONDS / 3600))hrs $(((SECONDS / 60) % 60))min $((SECONDS % 60))sec"
    info "$ELAPSED"

    AWS_VPC_ID=$(get_vpc_id "$TAG_PREFIX")
    info "vpc id :: $AWS_VPC_ID"

    create_tag "${AWS_VPC_ID}" "Key=Name,Value=$TAG_PREFIX"

    separator
    bump_step "CREATING NAT GATEWAYS :: CLOUDFORMATION"

    create_nat_gateway "${NAT_GATEWAY_STACK_NAME_A}" \
      "${NAT_GATEWAY_STACK_FILE}" \
      "${VPC_STACK_NAME}" \
      "A"

    ELAPSED="Elapsed: $((SECONDS / 3600))hrs $(((SECONDS / 60) % 60))min $((SECONDS % 60))sec"
    info "$ELAPSED"

    create_nat_gateway "${NAT_GATEWAY_STACK_NAME_B}" \
      "${NAT_GATEWAY_STACK_FILE}" \
      "${VPC_STACK_NAME}" \
      "B"

    ELAPSED="Elapsed: $((SECONDS / 3600))hrs $(((SECONDS / 60) % 60))min $((SECONDS % 60))sec"
    info "$ELAPSED"

    separator
    bump_step "CREATING SSH BASTION :: CLOUDFORMATION"

    create_ssh_bastion "${SSH_BASTION_STACK_NAME}" \
      "${SSH_BASTION_STACK_FILE}" \
      "${VPC_STACK_NAME}" \
      "${AWS_KEY_PAIR_NAME}"

    ELAPSED="Elapsed: $((SECONDS / 3600))hrs $(((SECONDS / 60) % 60))min $((SECONDS % 60))sec"
    info "Finished creating Cloudformation assets"
    info "$ELAPSED"

    separator
    bump_step "CREATING SECURITY GROUP"

    # sets AWS_SECURITY_GROUP_ID
    create_security_group "${AWS_VPC_ID}" "${AWS_SECGROUP_NAME}" "docker swarm security group"

    # sets AWS_SUBNET_ID
    get_subnet_id "SubnetAPrivate" "${TAG_PREFIX}"
    export AWS_PRIVATE_SUBNET_ID="${AWS_SUBNET_ID}"
    info "Found PRIVATE subnet id :: Cloudformation-logical-id: SubnetAPrivate :: ${AWS_PRIVATE_SUBNET_ID}"

    # sets AWS_SUBNET_ID
    get_subnet_id "SubnetAPublic" "${TAG_PREFIX}"
    export AWS_PUBLIC_SUBNET_ID="${AWS_SUBNET_ID}"
    info "Found PUBLIC subnet id :: Cloudformation-logical-id :: SubnetAPublic :: ${AWS_PUBLIC_SUBNET_ID}"

    set_phase_complete 1

    separator
    bump_step "CREATING VPC FLOW LOGS"

    create_role_for_flow_logs "$AWS_VPC_FLOW_LOGS_ROLE"
    get_role_arn_for_flow_logs "$AWS_VPC_FLOW_LOGS_ROLE"
    create_cloudwatch_log_group "$AWS_LOG_GROUP_NAME" "$AWS_LOG_GROUP_RETENTION"
    create_vpc_flow_logs

    set_phase_complete 2

    separator
    bump_step "CREATING SWARM MANAGER"

    create_manager

    separator
    bump_step "CONFIGURING SECURITY GROUP"

    get_aws_security_group "${AWS_SECGROUP_NAME}"
    open_docker_swarm_ports_in_security_group "${AWS_SECURITY_GROUP_ID}"
    open_http_port_in_security_group "${AWS_SECURITY_GROUP_ID}" "${AWS_VPC_IPV4_CIDR}"
    open_https_port_in_security_group "${AWS_SECURITY_GROUP_ID}" "${AWS_VPC_IPV4_CIDR}"

    separator
    bump_step "OPENING SSH TO INTERNAL NETWORK CIDR ${AWS_VPC_IPV4_CIDR}"

    open_ssh_port_in_security_group "${AWS_SECURITY_GROUP_ID}" "${AWS_VPC_IPV4_CIDR}"

    set_phase_complete 3

    separator
    bump_step "CREATING SWARM WORKERS"

    create_workers

    set_phase_complete 4

    separator
    bump_step "CREATING LOAD BALANCERS"

    get_and_export_ec2_instance_ids #sets AWS_EC2_INSTANCES_IDS

    warning "Waiting for instances to be ready"
    wait_for_ec2_instances "${AWS_EC2_INSTANCES_IDS}" "360"

    create_elb_http "${AWS_ELB_NAME}" "${AWS_PUBLIC_SUBNET_ID}" "${AWS_SECURITY_GROUP_ID}"

    set_phase_complete 5

    separator
    bump_step "ENABLING TERMINATION PROTECTION"

    get_and_export_ec2_instance_ids #sets AWS_EC2_INSTANCES_IDS
    iterate_and_enable_termination_protection "${AWS_EC2_INSTANCES_IDS}"

    AWS_PROVISIONING_COMPLETE="true"
    set_property "AWS_PROVISIONING_COMPLETE" "$AWS_PROVISIONING_COMPLETE"

    wait_for 5
  fi

  set_phase_complete 6

  separator
  bump_step "CONFIGURING DOCKER SWARM"

  info "Getting bastion host ip"

  BASTION_HOST=$(get_bastion_host_ip "${SSH_BASTION_STACK_NAME}")
  export BASTION_HOST

  info "Bastion host ip :: $BASTION_HOST"

  BASTION_ID=$(get_bastion_host_id "${SSH_BASTION_STACK_NAME}")
  export BASTION_ID

  create_tag "${BASTION_ID}" "Key=Type,Value=bastion"

  info "Bastion host ip :: ${BASTION_HOST}"
  BASTION_USER=${BASTION_USER:-"ec2-user"}
  export BASTION_USER

  run_swarm_init_ansible_playbook

  if [ "$POST_SWARM_SETUP" == "true" ]; then

    separator
    bump_step "SUBDOMAIN CREATION IN ROUTE 53"

    get_elb_dns_name "$AWS_ELB_NAME"
    create_registry_set_in_hosted_zone "${AWS_ROUTE_53_SUBDOMAIN}" "${AWS_ROUTE_53_DOMAIN}" "${AWS_ELB_DNS}"
  fi

  separator
  bump_step "FINISHED CREATING SWARM CLUSTER "
  separator
fi
