#!/bin/bash
docker-machine ls -f "{{.Name}}" | grep 'worker' | xargs docker-machine rm -f