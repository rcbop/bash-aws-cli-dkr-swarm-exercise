#!/bin/bash
#
# Requires colors.sh script
#
err_cleanup(){
  read line file <<<$(caller)
  set +x
  error "An error occurred in line $line of file $file:"
  error "Offending function :: $(sed "${line}q;d" "$file")"
  error "Offending line: $1"
  set -eE

  export FILTER="Name=tag:$AWS_FILTER_TAG_KEY,Values=$AWS_FILTER_TAG_VALUE"

  warning "Removing from PHASE: $CURRENT_PHASE backwards"

  if [ -z "$AWS_PROVISIONING_COMPLETE" ] || [ "$AWS_PROVISIONING_COMPLETE" == "false" ]; then
    if (( CURRENT_PHASE >= 5 )); then
      cleanup_elb

      wait_for 5
    fi

    if (( CURRENT_PHASE >= 4 )); then
      cleanup_workers

      wait_for 5
    fi

    if (( CURRENT_PHASE >= 2 )); then 
      cleanup_managers

      wait_for 5
    fi

    if (( CURRENT_PHASE >= 1 )); then    
      cleanup_flow_logs

      wait_for 5
    fi

    if (( CURRENT_PHASE >= 0 )); then
      # cleanup_vpc_cli
      cleanup_cloudformation_stacks
    fi
  fi

  separator
  error "FINISHED CLEANUP"
  ELAPSED="Elapsed: $((SECONDS / 3600))hrs $(((SECONDS / 60) % 60))min $((SECONDS % 60))sec"
  fatal "$ELAPSED"
}

exit_cleanup(){
  debug
  # warning "Cleaning Docker Machine"
  # rm -rf $HOME/.docker/machine/machines/$NODE_PREFIX*
  separator
  info "FINISHED EXIT CLEANUP"
  ELAPSED="Elapsed: $((SECONDS / 3600))hrs $(((SECONDS / 60) % 60))min $((SECONDS % 60))sec"
  info "TOTAL $ELAPSED"
}

