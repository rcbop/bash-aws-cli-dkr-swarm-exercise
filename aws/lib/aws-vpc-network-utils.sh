#!/bin/bash
#
# Requires colors.sh script
# Requires properties-utils.sh script
#
create_vpc(){
  debug

  info "Creating VPC"
  AWS_VPC_ID_DOC=$(create_vpc_subsh)

  AWS_VPC_ID=$(echo "$AWS_VPC_ID_DOC" | jq -r '.Vpc.VpcId')

  info "Creating tags for vpc"
  create_tag "${AWS_VPC_ID}" "${AWS_TAGS} Key=Name,Value=$VPC_NAME"

  [ -z "$AWS_VPC_ID" ] && fatal 'Error creating vpc'

  info "VPC created id: ${AWS_VPC_ID}"
  set_property "AWS_VPC_ID" "$AWS_VPC_ID"
}

create_vpc_subsh(){
  aws ec2 create-vpc --cidr-block "${AWS_VPC_IPV4_CIDR}"
}

create_subnet_in_vpc(){
  debug
  SUFIX=$1
  CIDR=$2

  info "Creating subnet ipv4 CIDR ${CIDR}"

  SUBNET_DOC=$(create_subnet_subsh "${CIDR}")
  AWS_SUBNET_ID=$(echo "$SUBNET_DOC" | jq -r '.Subnet.SubnetId')

  create_tag "$AWS_SUBNET_ID" "$AWS_TAGS Key=Name,Value=$TAG_PREFIX-$SUFIX"

  info "Subnet created id: ${AWS_SUBNET_ID}"
  set_property "AWS_SUBNET_ID" "$AWS_SUBNET_ID"
}

create_subnet_subsh(){
  aws ec2 create-subnet --availability-zone "${AWS_REGION}${AWS_AV_ZONE}" \
    --vpc-id "${AWS_VPC_ID}" \
    --cidr-block "${1}"
}

create_internet_gateway_vpc(){
  debug

  SUBNET_ID=$1

  create_internet_gateway_and_attach_to_vpc "$AWS_VPC_ID"

  create_route_table "$AWS_VPC_ID"

  create_route_in_route_table

  info "Associate route table to subnet"
  AWS_ROUTE_TABLE_ASSOCIATION_ID=$(associate_route_subsh "${SUBNET_ID}")

  [ -z "$AWS_ROUTE_TABLE_ASSOCIATION_ID" ] && fatal "Association failed"
  
  info "Route table association ID: ${AWS_ROUTE_TABLE_ASSOCIATION_ID}"
  set_property "AWS_ROUTE_TABLE_ASSOCIATION_ID" "$AWS_ROUTE_TABLE_ASSOCIATION_ID"
}

get_subnet_subsh(){
  aws ec2 describe-subnets --filters "Name=vpc-id,Values=${AWS_VPC_ID}" \
    --query 'Subnets[*].{ID:SubnetId,CIDR:CidrBlock}' | jq -r '.[0].ID'
}

associate_route_subsh(){
  aws ec2 associate-route-table  --subnet-id "${1}" \
    --route-table-id "${AWS_ROUTES_TABLE_ID}" | jq -r '.AssociationId'
}

create_internet_gateway_subsh(){
  aws ec2 create-internet-gateway
}

create_internet_gateway_and_attach_to_vpc(){
  info "Creating internet gateway"

  declare VPC_ID=$1

  AWS_INTERNET_GATEWAY_DOC=$(create_internet_gateway_subsh)
  AWS_INTERNET_GATEWAY_ID=$(echo "$AWS_INTERNET_GATEWAY_DOC" | jq -r '.InternetGateway.InternetGatewayId' )

  [ -z "$AWS_INTERNET_GATEWAY_ID" ] && fatal 'Error creating internet gateway'

  info "Internet Gateway ID: $AWS_INTERNET_GATEWAY_ID"
  set_property "AWS_INTERNET_GATEWAY_ID" "$AWS_INTERNET_GATEWAY_ID"

  create_tag "$AWS_INTERNET_GATEWAY_ID" "$AWS_TAGS Key=Name,Value=$TAG_PREFIX"

  info "Attach internet gateway to VPC"
  aws ec2 attach-internet-gateway \
    --vpc-id "${VPC_ID}" \
    --internet-gateway-id "${AWS_INTERNET_GATEWAY_ID}"
}

create_route_table(){
  info "Creating routes table"

  declare VPC_ID=$1

  ROUTES_TABLE_DOC=$(aws ec2 create-route-table --vpc-id "${VPC_ID}")
  AWS_ROUTES_TABLE_ID=$(echo "$ROUTES_TABLE_DOC" | jq -r '.RouteTable.RouteTableId')

  info "Created routes table id: $AWS_ROUTES_TABLE_ID"
  set_property "AWS_ROUTES_TABLE_ID" "$AWS_ROUTES_TABLE_ID"

  [ -z "$AWS_ROUTES_TABLE_ID" ] && fatal 'Error creating routes table'

  create_tag "$AWS_ROUTES_TABLE_ID" "$AWS_TAGS Key=Name,Value=$TAG_PREFIX"
}

create_route_in_route_table(){
  info "Creating route to redirect all traffic (0.0.0.0/0) to internet gateway"
  aws ec2 create-route --route-table-id "${AWS_ROUTES_TABLE_ID}" \
    --destination-cidr-block "0.0.0.0/0" \
    --gateway-id "${AWS_INTERNET_GATEWAY_ID}"

  create_tag "$AWS_ROUTES_TABLE_ID" "$AWS_TAGS"

  info "Listing routes tables"
  aws ec2 describe-route-tables --route-table-id "${AWS_ROUTES_TABLE_ID}"
}

allocate_elastic_ip(){
  debug

  ELASTIC_IP_DOC=$(aws ec2 allocate-address --output json)
  ELASTIC_IP=$(echo "$ELASTIC_IP_DOC" | jq -r '.PublicIp')
  AWS_ELASTIC_IP_ALLOCATION_ID=$(echo "$ELASTIC_IP_DOC" | jq -r '.AllocationId')

  [ -z "${AWS_ELASTIC_IP_ALLOCATION_ID}" ] && fatal "ERROR creating elastic ip"

  create_tag "$AWS_ELASTIC_IP_ALLOCATION_ID" "$AWS_TAGS"

  info "Elastic ip created ID: ${AWS_ELASTIC_IP_ALLOCATION_ID}"
  set_property "AWS_ELASTIC_IP_ALLOCATION_ID" "${AWS_ELASTIC_IP_ALLOCATION_ID}"
}

associate_elastic_ip_to_manager(){
  debug

  set -x

  EC2_INSTANCE_ID=$(get_ec2_instanceid_subsh 'manager')

  get_inet_interface_ip "${DOCKER_SWARM_MANAGER_NAME}"
  info "Manager created IP address ${NODE_IP_ADDRESS}"

  info "Associate previously created elastic ip to manager node"
  associate_elastic_ip
}

associate_elastic_ip(){
  debug

  info "Associate elastic ip"
  
  AWS_ELASTIC_IP_ASSOCIATION_ID=$(associate_address_subsh)

  [ -z "$AWS_ELASTIC_IP_ASSOCIATION_ID" ] && fatal "ERROR in elastic ip association"

  info "Elastic ip address association ID: ${AWS_ELASTIC_IP_ASSOCIATION_ID}"
  set_property "AWS_ELASTIC_IP_ASSOCIATION_ID" "$AWS_ELASTIC_IP_ASSOCIATION_ID"
}

get_ec2_instanceid_subsh(){
  declare TYPE=$1
  aws ec2 describe-instances --filters "Name=tag:$AWS_FILTER_TAG_KEY,Values=$AWS_FILTER_TAG_VALUE,Name=tag:Type,Values=$TYPE" \
    --output text | jq -r '.[][].Instances[] | select(.State.Name == "running") | .InstanceId'
}

associate_address_subsh(){
  aws ec2 associate-address --instance-id "${EC2_INSTANCE_ID}" \
    --allocation-id "${AWS_ELASTIC_IP_ALLOCATION_ID}" | jq -r '.AssociationId'
}

get_vpc_id(){
  local PROJECT=$1
  aws ec2 describe-vpcs --filters "Name=tag:Project,Values=$PROJECT" --query "Vpcs[*].VpcId" --output text
}

cleanup_elasticip(){
  warning "Releasing elastic ip address :: ${AWS_ELASTIC_IP_ALLOCATION_ID}"
  aws ec2 describe-addresses --filters "$FILTER" \
    --query "Addresses[*].AllocationId" \
    --output text | xargs -i -r aws ec2 release-address --allocation-id {}
}

cleanup_vpc_cli(){
  warning "Deleting VPC :: ${AWS_VPC_ID}"

  export FILTER="Name=tag:$AWS_FILTER_TAG_KEY,Values=$AWS_FILTER_TAG_VALUE"

  VPC_ID=$(get_vpc_id "$TAG_PREFIX")

  warning "Removing security group"
  aws ec2 describe-security-groups --filters "$FILTER" \
    --query 'SecurityGroups[*].GroupId' \
    --output text | xargs -i -r aws ec2 delete-security-group --group-id {}
  
  wait_for 5
  
  warning "Removing subnet"
  aws ec2 describe-subnets --filters "$FILTER" \
    --query 'Subnets[*].SubnetId' \
    --output text | xargs -i -r aws ec2 delete-subnet --subnet-id {}

  wait_for 5

  warning "Removing route table"
  aws ec2 describe-route-tables --filters "$FILTER" \
    --query "RouteTables[*].RouteTableId" \
    --output text | xargs -i -r aws ec2 delete-route-table --route-table-id {}

  wait_for 5

  warning "Detach internet gateway"
  aws ec2 describe-internet-gateways --filters "$FILTER" \
    --query "InternetGateways[*].InternetGatewayId" \
    --output text | xargs -i -r aws ec2 detach-internet-gateway --internet-gateway-id {} --vpc-id "${VPC_ID}"

  wait_for 5

  warning "Removing internet gateway"
  aws ec2 describe-internet-gateways --filters "$FILTER" \
    --query "InternetGateways[*].InternetGatewayId" \
    --output text | xargs -i -r aws ec2 delete-internet-gateway --internet-gateway-id {}

  wait_for 5

  warning "Removing vpc"
  [ ! -z "${VPC_ID}" ] && aws ec2 delete-vpc --vpc-id "${VPC_ID}"

}

cleanup_desassociate_elasticip(){
  warning "Desassociate elastic ip adress :: ${AWS_ELASTIC_IP_ASSOCIATION_ID}"
  aws ec2 describe-addresses --filters "$FILTER" \
    --query "Addresses[*].AssociationId" \
    --output text | xargs -i aws ec2 disassociate-address --association-id {}
}

get_subnet_id(){
  debug
  local PROJECT=$1
  local CLOUDFORMATION_LOGICAL_ID=$2

  AWS_SUBNET_ID=$(get_subnet_id_subsh "${PROJECT}" "${CLOUDFORMATION_LOGICAL_ID}")
}

get_subnet_id_subsh(){
  local PROJECT=$1
  local CLOUDFORMATION_LOGICAL_ID=$2
  aws ec2 describe-subnets --region "${AWS_REGION}" | jq -r ".Subnets[] | { id: .SubnetId, tags: (.Tags // []) } | select(.tags[].Value==\"${CLOUDFORMATION_LOGICAL_ID}\") | select(.tags[].Value==\"${PROJECT}\") | .id"
}