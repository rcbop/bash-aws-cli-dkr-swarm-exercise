#!/bin/bash
cp "$(pwd)/template/aws-variables-templ.properties" "$(pwd)/aws-variables.properties"
if [ ! -f "$(pwd)/password.properties" ]; then
    cp "$(pwd)/template/password-templ.properties" "$(pwd)/password.properties"
else
    echo 'Password.properties already exists'
fi