#!/bin/bash
#
# Requires colors.sh script
#
open_docker_swarm_ports_in_security_group(){
  debug

  info "Opening docker swarm overlay network ports in security group"

  local AWS_SECURITY_GROUP_ID=$1

  IFS=$'\n'
  for CURRENT_PORT in "${DOCKER_SWARM_PORTS_TO_OPEN_ARRAY[@]}"
  do
    PROTOCOL="${CURRENT_PORT%%:*}"
    PORT="${CURRENT_PORT##*:}"
    info "opening port protocol: $PROTOCOL port: $PORT"

    aws ec2 authorize-security-group-ingress --group-id "${AWS_SECURITY_GROUP_ID}" \
      --protocol "${PROTOCOL}" \
      --port "${PORT}" \
      --source-group "${AWS_SECURITY_GROUP_ID}"
  done
}

open_http_port_in_security_group(){
  debug

  local AWS_SECURITY_GROUP_ID=$1
  local CIDR=$2

  if [ ! -z "$INBOUND_PORT_80" ]; then
    info "port 80 found in docker-machine security group"
  else
    warning "port 80 not found in docker-machine security group. Adding..."
    aws ec2 authorize-security-group-ingress --group-id "${AWS_SECURITY_GROUP_ID}" \
      --protocol "tcp" \
      --port "80" \
      --cidr "${CIDR}"
  fi
}

open_https_port_in_security_group(){
  debug

  local AWS_SECURITY_GROUP_ID=$1
  local CIDR=$2

  if [ ! -z "$INBOUND_PORT_443" ]; then
    info "port 443 found in docker-machine security group"
  else
    warning "port 443 not found in docker-machine security group. Adding..."
    aws ec2 authorize-security-group-ingress --group-id "${AWS_SECURITY_GROUP_ID}" \
      --protocol "tcp" \
      --port "443" \
      --cidr "${CIDR}"
  fi
}

open_ssh_port_in_security_group(){
  debug

  local AWS_SECURITY_GROUP_ID=$1
  local CIDR=$2

  if [ ! -z "$INBOUND_PORT_22" ]; then
    info "port 22 found in docker-machine security group"
  else
    warning "port 22 not found in docker-machine security group. Adding..."
    open_ssh_port_direct "${AWS_SECURITY_GROUP_ID}" "${CIDR}"
  fi
}

open_ssh_port_direct(){
  local AWS_SECURITY_GROUP_ID=$1
  local CIDR=$2
  aws ec2 authorize-security-group-ingress --group-id "${AWS_SECURITY_GROUP_ID}" \
      --protocol "tcp" \
      --port "22" \
      --cidr "${CIDR}"
}

close_ssh_port_in_security_group(){
  debug

  declare CIDR=$1

  info "Closing port 22 found in security group"

  set -x
  aws ec2 revoke-security-group-ingress --group-id "${AWS_SECURITY_GROUP_ID}" \
      --protocol "tcp" \
      --port "22" \
      --cidr "$CIDR"
  set +x
}

get_aws_security_group(){
  debug

  local SECURITY_GROUP_NAME=$1

  info "Getting ${DOCKER_SWARM_MANAGER_NAME} security group information"

  SECURITY_GROUP_DOC=$(aws ec2 describe-security-groups | jq -r ".SecurityGroups[] | select(.GroupName==\"$SECURITY_GROUP_NAME\")")
  AWS_SECURITY_GROUP_ID=$(echo "$SECURITY_GROUP_DOC" | jq -r ".GroupId" | tr '\n' ' ' | xargs echo | cut -d' ' -f1)

  debug "AWS_SECURITY_GROUP_ID :: $AWS_SECURITY_GROUP_ID"

  [ -z "$AWS_SECURITY_GROUP_ID" ] && fatal "ERROR in querying security group ID"

  info "Security group id ${AWS_SECURITY_GROUP_ID}"
  set_property "AWS_SECURITY_GROUP_ID" "$AWS_SECURITY_GROUP_ID"

  INBOUND_PORT_22=$(echo "$SECURITY_GROUP_DOC" | jq -r '.IpPermissions[] | select(.FromPort==22)')
  INBOUND_PORT_80=$(echo "$SECURITY_GROUP_DOC" | jq -r '.IpPermissions[] | select(.FromPort==80)')
  INBOUND_PORT_443=$(echo "$SECURITY_GROUP_DOC" | jq -r '.IpPermissions[] | select(.FromPort==443)')
}

create_key_pair(){
  debug

  aws ec2 create-key-pair --key-name "${KEY_PAIR_CREATED_NAME}" \
    --query 'KeyMaterial' \
    --output text > "${KEY_PAIR_CREATED_FILE}"

  chmod 400 "${KEY_PAIR_CREATED_FILE}"
}

create_security_group(){
  debug
  local VPC_ID=$1
  local GROUP_NAME=$2
  local DESCRIPTION=$3

  AWS_SECURITY_GROUP_ID=$(create_security_group_subsh "${VPC_ID}" "${GROUP_NAME}" "${DESCRIPTION}")

  create_tag "$AWS_SECURITY_GROUP_ID" "$AWS_TAGS"
}

create_security_group_subsh(){
  local VPC_ID=$1
  local GROUP_NAME=$2
  local DESCRIPTION=$3
  aws ec2 create-security-group --vpc-id "${VPC_ID}" \
    --group-name "${GROUP_NAME}" \
    --description "${DESCRIPTION}" | jq -r ".GroupId"
}

create_tag(){
  debug
  declare RESOURCES=$1
  declare TAGS=$2

  info "Creating tags for $RESOURCES :: $TAGS"

  aws ec2 create-tags --tags "$TAGS" --resources "$RESOURCES"
}
