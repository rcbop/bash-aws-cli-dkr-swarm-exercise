#!/bin/bash
docker-machine ls -f "{{.Name}}" | grep 'manager' | xargs docker-machine rm -f