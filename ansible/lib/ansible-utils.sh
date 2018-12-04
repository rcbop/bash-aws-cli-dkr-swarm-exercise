#!/bin/bash
#
# Requires colors.sh script
#

setup_ansible_roles(){
  local ROLE=$1
  mkdir -p "${BASEDIR}/ansible/roles"

  info "Installing ansible roles :: $ROLE"
  ansible-galaxy install "${ROLE}" --roles-path="${BASEDIR}/ansible/roles"

  tree "${BASEDIR}/ansible/roles"
}

run_swarm_init_ansible_playbook(){
  debug

  # get all hosts created
  UNDERLINED_TAG_PREFIX=${TAG_PREFIX//[ -]/_}

  debug "tag prefix with underline :: $UNDERLINED_TAG_PREFIX"

  ALL_HOSTS="${AWS_REGION}:&tag_Project_${UNDERLINED_TAG_PREFIX}:&tag_Environment_${ENVIRONMENT}:"
  DYNAMIC_INVENTORY_ALL_HOSTS="dynamic_hosts=${ALL_HOSTS}"

  # setup_ansible_roles "avinetworks.docker"

  run_playbook "install-docker" "ec2.py" "${DYNAMIC_INVENTORY_ALL_HOSTS}"
  wait_for 5
  
  run_playbook "install-dependencies-aws-linux" "ec2.py" "${DYNAMIC_INVENTORY_ALL_HOSTS}"

  wait_for 5

  run_playbook "docker-cleanup-cron" "ec2.py" "${DYNAMIC_INVENTORY_ALL_HOSTS}"
  wait_for 10

  # separates hosts into managers and workers
  MANAGERS_AND_WORKERS="manager_dynamic_hosts=${ALL_HOSTS}&tag_Type_manager workers_dynamic_hosts=${ALL_HOSTS}&tag_Type_worker"

  run_playbook "docker-swarm-provision" "ec2.py" "${MANAGERS_AND_WORKERS}"
  wait_for 10
}

is_inside_docker(){
  debug
  [ -f /.dockerenv ]
}

run_playbook(){
  debug
  
  export ANSIBLE_NOCOWS=1
  export ANSIBLE_NOCOLOR=0
  export ANSIBLE_FORCE_COLOR=true
  export ANSIBLE_RETRY_FILES_ENABLED=${ANSIBLE_RETRY_FILES_ENABLED:-false}
  export ANSIBLE_STDOUT_CALLBACK=${ANSIBLE_STDOUT_CALLBACK:-debug}
  export ANSIBLE_CONFIG="${BASEDIR}/ansible/ansible.cfg"

  # ssh bastion user and host must be set
  : ${BASTION_USER:?}
  : ${BASTION_HOST:?}
  
  local PLAYBOOK="$BASEDIR/ansible/playbook/$1.yml"
  local INVENTORY="$BASEDIR/ansible/inventory/$2"
  local EXTRA_VARS=$3

  echo "Running $PLAYBOOK"
  echo "Using $INVENTORY"

  AWS_KEY_ID=${AWS_KEY_ID:="$(aws configure get aws_access_key_id --profile ${AWS_PROFILE})"}
  AWS_SECRET_KEY=${AWS_SECRET_KEY:="$(aws configure get aws_secret_access_key --profile ${AWS_PROFILE})"}

  EXTRA_PARAMS=""

  if ! is_inside_docker; then
    info "NOT Running inside docker"
    EXTRA_PARAMS+="--extra-vars 'ansible_ssh_private_key_file=${AWS_KEY_PAIR_PATH}'"
  else 
    info "Running inside docker"
  fi

  EXTRA_PARAMS+="--extra-vars '${EXTRA_VARS} ansible_ssh_user=${AWS_CLI_USER} aws_cli_user=${AWS_CLI_USER} aws_region=${AWS_REGION} aws_profile=${AWS_PROFILE} aws_key_id=${AWS_KEY_ID} aws_secret_key=${AWS_SECRET_KEY} aws_registry_id=${AWS_REGISTRY_ID}'"

  set -x
  eval ansible-playbook -i "${INVENTORY}" "${PLAYBOOK}" -e 'host_key_checking=False' "${EXTRA_PARAMS}" -v
  set +x
}

# oneliner with \n as separator
get_workers_ips(){
  aws ec2 describe-instances --filters "Name=tag:Name,Values=$NODE_PREFIX*worker*" "Name=tag:Type,Values=worker" \
    --query "Reservations[*].Instances[*].PublicIpAddress" \
    --output text | sed -e :a -e N -e '$!ba' -e 's/\n/\\n/g'
}

get_managers_ips(){
  aws ec2 describe-instances --filters "Name=tag:Name,Values=$NODE_PREFIX*manager*" "Name=tag:Type,Values=manager" \
    --query "Reservations[*].Instances[*].PublicIpAddress" \
    --output text
}

create_aws_ansible_inventory_file(){
  debug

  MANAGER_IP=$(get_managers_ips)
  WORKERS_IPS_STR=$(get_workers_ips)

  info "WORKERS IPS :: "
  echo "$WORKERS_IPS_STR"

  if is_osx; then
    warning "GNU sed must be available as gsed"

    gsed -e "s_##MANAGERIP##_${MANAGER_IP}_" \
      -e "s_##EC2USER##_${AWS_EC2_AMI_DEFAULT_USER}_" \
      -e "s_##KEYPATH##_${AWS_KEY_PAIR_PATH}_" \
      -e 's_##WORKERSIPS##_'"${WORKERS_IPS_STR}"'_' \
      "${BASEDIR}"/ansible/inventory/AWS.tmpl > "${BASEDIR}"/ansible/inventory/AWS
  else
    sed -e "s_##MANAGERIP##_${MANAGER_IP}_" \
      -e "s_##EC2USER##_${AWS_EC2_AMI_DEFAULT_USER}_" \
      -e "s_##KEYPATH##_${AWS_KEY_PAIR_PATH}_" \
      -e 's_##WORKERSIPS##_'"${WORKERS_IPS_STR}"'_' \
      "${BASEDIR}"/ansible/inventory/AWS.tmpl > "${BASEDIR}"/ansible/inventory/AWS
  fi
}

is_osx(){
  debug
  [[ "$(uname)" == *"arwin" ]]
}
