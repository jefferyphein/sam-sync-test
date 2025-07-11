#!/usr/bin/env bash

# Arguments to this script are as follows:
#
#   $1 -> the artifacts directory (i.e. the build directory for the lambda).
#   $2 -> an argument indicating to run the protected command. Any value
#         will suffice, as long as it is non-empty.
#

set -euo pipefail

# Input arguments.
artifacts_dir="$1"
run_with_lock="${2:-}"

function pip_install() {
  requirements="$1"
  install_dir="$2"
  log_file="$3"
  pip install -r "$requirements" -t "$install_dir" >> "$log_file" 2>&1 
}

# Assume that the artifacts directory contains "requirements.txt"
requirements="${artifacts_dir}/requirements.txt"
if [ ! -e "$requirements" ]; then
  echo "Artifacts directory must contain 'requirements.txt' file."
  exit 1
fi

# Find the .aws-sam/ root directory.
aws_sam_dir="${artifacts_dir%/.aws-sam/*}/.aws-sam"

# If the "flock" command doesn't exist, simply "pip install" into artifacts directory.
if ! command -v flock >/dev/null; then
  log_file="${artifacts_dir%/}.log"
  pip_install "$requirements" "$artifacts_dir" "$log_file"
  rc=$?
  exit $rc
fi

# Calculate the SHA1 hash of the requirements.txt file.
requirements_sha1=$(sha1sum "$requirements" | awk '{print $1}')

# Determine the paths we need and create directories, if necessary.
install_dir="$aws_sam_dir/build/pip-install/$requirements_sha1"
log_file="$aws_sam_dir/build/pip-install/$requirements_sha1.log"
lock_file="$install_dir/.aws-sam.lock"
mkdir -p "$install_dir"

# This block is run outside of the lock.
if [ -z "$run_with_lock" ]; then
  # Block until the lock is acquired and the protected code returns.
  flock "$lock_file" "$0" "$artifacts_dir" "run_with_lock"

  # Once the lock is released, copy the installed artifacts only if certain
  # conditions are met.
  if [ -e "$install_dir/.INSTALLED" ] && [ ! -e "$install_dir/.FAILED" ]; then
    cp -r "$install_dir/." "$artifacts_dir"
  fi

# This block is run within the lock.
else
  # NOTE: All commands within this block are protected under the file lock.

  # If the .FAILED file exists, fail immediately.
  if [ -e "$install_dir/.FAILED" ]; then
    echo "Install failed, refusing to proceed."
    exit 1
  fi

  # Only run "pip install" if the .INSTALLED file doesn't exist.
  if [ ! -e "$install_dir/.INSTALLED" ]; then
    pip install -r "$requirements" -t "$install_dir" >> "$log_file" 2>&1
    rc=$?
    if [ ! -n $rc ]; then
      echo "Installation failed! Dumping logs..."
      cat "$log_file"
      touch "$install_dir/.FAILED"
      exit 1
    fi
    # Remove installation artifacts.
    find "$install_dir" -name "*.pyc" -type f -delete
    find "$install_dir" -name __pycache__ -type d -delete
    # Drop a file indicating successful installation.
    touch "$install_dir/.INSTALLED"
  fi

  # NOTE: The file lock will be released immediately after this script terminates.
fi
