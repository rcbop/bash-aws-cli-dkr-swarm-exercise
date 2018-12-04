#!/bin/bash
#
#
#
get_ebs_volume_for_ec2_instance_array(){
    local WHITE_LIST="$1"

    aws ec2 describe-instances --query 'Reservations[].Instances[].{MachineName:Tags[?Key==`Name`].Value,Name:ImageId,InstanceId:InstanceId,VolumeInfo:BlockDeviceMappings}' \
        | jq " as \$whitelist | .[] | select(.InstanceId as \$in | \$blacklist | index(\$in))"
}