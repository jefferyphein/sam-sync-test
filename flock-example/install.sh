#!/usr/bin/env bash

# Arguments to this script are as follows:
#
#   $1 -> the artifacts directory (i.e. the build directory for the lambda)
#   $2 -> an argument indicating to run the protected locked command
#
# We assume that this directory contains a file named "requirements.txt"
#

# Calculate the SHA1 hash of the requirements.txt file.
requirements="${1}/requirements.txt"
requirements_sha1=$(sha1sum "$requirements" | awk '{print $1}')

# Find the .aws-sam/ root directory.
aws_sam_dir="${1%/.aws-sam/*}/.aws-sam"

# Determine the paths we need and create directories, if necessary.
install_dir="$aws_sam_dir/pip-install/$requirements_sha1"
log_file="$aws_sam_dir/pip-install/$requirements_sha1.log"
lock_file="$install_dir/.aws-sam.lock"
mkdir -p "$install_dir"

# This block is run outside of the lock.
if [ -z "$2" ]; then
  flock "$lock_file" "$0" "$1" "run_with_lock"
  if [ -e "$install_dir/.INSTALLED" ] && [ ! -e "$install_dir/.FAILED" ]; then
    cp -r "$install_dir/." "$1"
  fi

# This block is run within the lock.
else
  # Only run "pip install" if the .INSTALLED file doesn't exist.
  # NOTE: We cannot use the lock file here, because it will be created by "flock".
  if [ -e "$install_dir/.FAILED" ]; then
    echo "Install failed, refusing to proceed."
    exit 1
  elif [ ! -e "$install_dir/.INSTALLED" ]; then
    pip install -r "$requirements" -t "$install_dir" >> "$log_file" 2>&1
    rc=$?
    if [ ! -n $rc ]; then
      echo "Installation failed! Dumping logs..."
      cat "$log_file"
      touch "$install_dir/.FAILED"
      exit 1
    fi
    touch "$install_dir/.INSTALLED"
  fi
fi
