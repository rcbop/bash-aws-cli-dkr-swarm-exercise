#!/bin/bash

BASEDIR=$(dirname "$0")
IMAGE_NAME=${IMAGE_NAME:-"aws-docker-swarm-provisioner"}

docker_build(){
  docker build -t "${IMAGE_NAME}" \
    --build-arg=AWS_KEY_ID="${AWS_KEY_ID}" \
    --build-arg=AWS_SECRET_ID="${AWS_SECRET_KEY}" \
    -f "${BASEDIR}"/../Dockerfile .
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
    echo "Building docker image :: ${IMAGE_NAME}"
    docker_build
fi