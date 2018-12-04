#!/bin/bash

# Fails if KEY_ID and SECRET are empty
: ${AWS_KEY_ID:?}
: ${AWS_SECRET_KEY:?}
: ${AWS_KEY_PAIR_PATH:?'Please provide path to ssh key for bind mount into docker container'}

BASEDIR=$(dirname "$0")
IMAGE_NAME=${IMAGE_NAME:-"aws-docker-swarm-provisioner"}
ENVFILE=${ENVFILE:-"aws-variables.properties"}

[ ! -f "${AWS_KEY_PAIR_PATH}" ] && echo "Private key file not found in path" && exit 1
[ ! -f "${ENVFILE}" ] && echo "Environment file not found in :: $ENVFILE" && exit 1

docker_run(){
    docker run \
        -e AWS_KEY_ID="${AWS_KEY_ID}" \
        -e AWS_SECRET_KEY="${AWS_SECRET_KEY}" \
        -e DEBUG="${DEBUG:-false}" \
        -e NO_COLORS="${NO_COLORS:-false}" \
        -e AWS_PROVISIONING_COMPLETE="${AWS_PROVISIONING_COMPLETE:-false}" \
        -v "${AWS_KEY_PAIR_PATH}":/root/.ssh/id_rsa \
        -v "${BASEDIR}"/../"${ENVFILE}":/app/"${ENVFILE}" \
        -v "${PWD}/logs":/app/logs \
        -i "${IMAGE_NAME}"
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
    echo "Running docker image :: ${IMAGE_NAME}"
    docker_run
fi