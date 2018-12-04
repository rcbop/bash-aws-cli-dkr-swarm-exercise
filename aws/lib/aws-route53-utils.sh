#!/bin/bash
#
# Requires colors.sh script
# Requires properties-utils.sh script
#
create_registry_set_in_hosted_zone(){
  debug

  declare SUBDOMAIN=$1
  declare DOMAIN=$2
  declare VALUE=$3

  info "Creating $SUBDOMAIN record in $DOMAIN targeting $VALUE"

  zone_name="${DOMAIN}"
  wait_for_sync=true

  add_dns_record "$SUBDOMAIN.$DOMAIN" "$VALUE" 
}

# configs:
#   - action=CREATE
#   - ttl=300
#   - record_type=A
#   - wait_for_sync=false
add_dns_record() {
	record_name=$1
	record_value=$2

	[[ -z $record_name  ]] && info "record_name is: $record_name" && exit 1
	[[ -z $record_value ]] && info "record_value is: $record_value" && exit 1

	## set some defaults if variables haven't been overridden on script execute
	declare zone_name=${zone_name:-$record_value}
	declare action=${action:-CREATE}
	declare record_type=${record_type:-A}
	declare ttl=${ttl:-300}
	declare wait_for_sync=${wait_for_sync:-false}

	change_id=$(submit_resource_record_change_set) || fatal 'Unable to perform dns record change'
	info "Record change submitted! Change Id: $change_id"
	if $wait_for_sync; then
		info "Waiting for all Route53 DNS to be in sync..."
		until [[ $(get_change_status $change_id) == "INSYNC" ]]; do
		 	echo -n "."
		 	sleep 5
		done
		info "!"
		info "Your record change has now propogated."
	fi
}

change_batch() {
	jq -c -n "{\"Changes\": [{\"Action\": \"$action\", \"ResourceRecordSet\": {\"Name\": \"$record_name\", \"Type\": \"$record_type\", \"TTL\": $ttl, \"ResourceRecords\": [{\"Value\": \"$record_value\"} ] } } ] }"
}

get_change_status() {
	aws route53 get-change --id $1 "${CLI_EXTRA_PARAMS}" | jq -r '.ChangeInfo.Status'
}

hosted_zone_id() {
  aws route53 list-hosted-zones | jq -r ".HostedZones[] | select(.Name | contains(\"${zone_name}\")) | .Id" | cut -d'/' -f3
}

submit_resource_record_change_set() {
	HOSTED_ZONE_ID=$(hosted_zone_id)
	[ -z "$HOSTED_ZONE_ID" ] && fatal 'Hosted zone not found'
	CHANGE_BATCH=$(change_batch)
	[ -z "$CHANGE_BATCH" ] && fatal 'Change batch not found'

	aws route53 change-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" \
    	--change-batch "$CHANGE_BATCH" | jq -r '.ChangeInfo.Id' | cut -d'/' -f3
}