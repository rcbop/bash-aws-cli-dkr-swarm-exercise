#!/bin/bash
#
# Requires colors.sh script
#
check_current_script_dependencies(){
  debug
  
  check_dos2unix
  check_awk
  check_python
  check_pip
  check_aws_cli
  check_jq
  check_ansible
}

check_python(){
  debug
  info "Checking Python 2.7"

  if command -v python &>/dev/null; then
    pyversion=$( { python --version; } 2>&1 )
    info "$pyversion"
    version_check=$(echo "$pyversion" | grep '2.7')
    if [ -z "$version_check" ]; then
      fatal "Python is not on version 2.7"
    fi
    info "Python installed!"
  else

    error "Python is not installed"
    fatal "Please install python 2.7 manually, exiting..."
  fi
}

check_dos2unix(){
  debug
  info "Checking dos2unix"

  if command -v dos2unix &>/dev/null; then
    info "dos2unix version:: "
    dos2unix --version || echo 'busybox stripped version'
  else
    error "dos2unix is not installed"
    fatal "Please install dos2unix using package manager"
  fi
}

check_pip(){
  debug
  info "Checking Pip"

  if command -v pip &>/dev/null; then
    pipversion=$(pip --version )
    info "$pipversion"
    info "Pip installed!"
  else
    error "Pip is not installed"
    warning "Attempting to install pip..."

    curl -L https://bootstrap.pypa.io/get-pip.py | python
    [ $? != 0 ] && fatal "Error installing pip, please install pip manually, exiting..."
  fi
}

check_yq(){
  debug
  info "Checking yq (.yml CLI processor)"

  if command -v yq &>/dev/null; then
    yqversion=$(yq --version 2>&1)
    info "$yqversion"
    info "yq installed!"
  else
    error "yq is not installed"
    warning "Attempting to install using pip..."

    pip install yq
    [ $? != 0 ] && fatal "Error installing yq, please install yq manually, exiting..."
  fi
}

check_jq(){
  debug
  info "Checking jq (JSON CLI processor)"

  if command -v jq &>/dev/null; then
    jqversion=$(jq --version 2>&1 || echo 'busybox version')
    info "$jqversion"
    info "jq installed!"
  else
    error "jq is not installed"
    warning "Attempting to install using pip..."

    pip install jq
    [ $? != 0 ] && fatal "Error installing jq, please install jq manually, exiting..."
  fi
}

check_aws_cli(){
  debug
  info "Checking AWS CLI"

  if command -v aws &>/dev/null; then
    awsversion=$(unset AWS_PROFILE && aws --version)
    info "$(echo "$awsversion" | tr -d '\n')"
    info "AWS CLI installed!"
  else
    error "AWS CLI is not installed"
    warning "Attempting to install AWS CLI..."

    pip install awscli
    [ $? != 0 ] && fatal "Error installing awscli, please install it manually, exiting..."
  fi
}

check_ansible(){
  debug
  
  info "Checking ansible"

  if command -v ansible &>/dev/null; then
    ansible_version=$(ansible --version)
    info "$(echo "$ansible_version" | tr -d '\n')"
    info "ANSIBLE installed!"
  else
    error "ANSIBLE is not installed"
    warning "Attempting to install ANSIBLE..."

    pip install ansible
    [ $? != 0 ] && fatal "Error installing ansible, please install it manually, exiting..."
  fi
}

check_awk(){
  debug

  info "Checking awk"

  if command -v awk &>/dev/null; then
    AWK_VERSION=$(awk --version 2>/dev/null || echo 'busybox version')
    info "AWK installed"
    info "$AWK_VERSION"
  else
    fatal "Error please install awk"
  fi
}

check_docker_machine(){
  debug

  info "Checking awk"

  if command -v docker-machine &>/dev/null; then
    DOCKER_MACHINE_VERSION=$(docker-machine --version)
    info "docker-machine installed"
    info "$DOCKER_MACHINE_VERSION"
  else
    fatal "Error please install docker-machine https://docs.docker.com/machine/install-machine/"
  fi
}

manual_install_aws_cli(){
  debug

  TMP_DIR=awstmp
  mkdir "$TMP_DIR" && cd "$TMP_DIR"
  curl -o awscli.zip https://s3.amazonaws.com/aws-cli/awscli-bundle.zip

  unzip awscli.zip
  ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws

  cd "$ORIGIN"
  rm -rf "$TMP_DIR"
}
