#!/usr/bin/env bash
set -e -o pipefail
#/ Usage:
#/    set_property key value filename
#/ Alternative:
#/
#/ export PROPERTIES_FILE=myproperties
#/    set_property key value
#/ --------------------------------------------------------------------------------
#/ Author: Rogério Castelo Branco Peixoto
#/ --------------------------------------------------------------------------------
# Requires colors.sh script
#
set_property(){
  debug "params $1 $2 $3"

  if [ -z "$1" ]; then
    fatal "No parameters provided, exiting..."
  fi
  if [ -z "$2" ]; then
    fatal "Key provided, but no value, exiting..."
  fi
  if [ -z "$3" ] && [ -z "$PROPERTIES_FILE_OUT" ]; then
    fatal "No file provided or PROPERTIES_FILE is not set, exiting..."
  fi

  if [ "$PROPERTIES_FILE_OUT" ] && [ "$3" ]; then
      fatal "PROPERTIES_FILE variable is set AND filename in comamnd! Use only or the other. Exiting..."
  else
    if [ "$3" ] && [ ! -f "$3" ]; then
      fatal "File in command NOT FOUND!"
    elif [ "$PROPERTIES_FILE_OUT" ] && [ ! -f "$PROPERTIES_FILE_OUT" ]; then
      fatal "File in PROPERTIES_FILE variable NOT FOUND!"
    fi
  fi

  if [ "$PROPERTIES_FILE_OUT" ]; then
    debug "Properties file set $PROPERTIES_FILE_OUT"
    file=$PROPERTIES_FILE_OUT
  else
    file=$3
  fi

  tempfile=$(mktemp "/tmp/$file.XXXXXX")

  if ! grep "$1=" "$file"; then
    info "Saving $1 new variable to $file"
    cat $file >> $tempfile
    echo "$1=$2" >> $tempfile
  else
    info "Updating $1 variable in $file"
    awk -v pat="^$1=" -v value="$1=$2" '{ if ($0 ~ pat) print value; else print $0; }' "$file" > "$tempfile"
  fi

  sorted_tempfile=$(mktemp "/tmp/$file.XXXXXX")

  sort "$tempfile" > "$sorted_tempfile"
  tempfile=$sorted_tempfile

  mv "$tempfile" "$file"
}

check_input_file_exists(){
  debug
  IN_FILE=$1
  if [ ! -f "$IN_FILE" ]; then
    fatal "Please create input variables file in :: ${1}"
  fi
}

convert_properties_crlf_to_unix(){
  debug
  IN_FILE=$1
  if [[ $(file "${IN_FILE}") =~ CRLF ]]; then
    dos2unix "${IN_FILE}"
  fi
}
