#!/bin/bash

# Copyright 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


set -e

source $(dirname $0)/config-go.sh

# Go to the top of the tree.
cd "${KUBE_REPO_ROOT}"

# Check for `go` binary and set ${GOPATH}.
kube::setup_go_environment


find_test_dirs() {
  cd src/${KUBE_GO_PACKAGE}
  find . -not \( \
      \( \
        -wholename './output' \
        -o -wholename './_output' \
        -o -wholename './release' \
        -o -wholename './target' \
        -o -wholename '*/third_party/*' \
        -o -wholename '*/Godeps/*' \
      \) -prune \
    \) -name '*_test.go' -print0 | xargs -0n1 dirname | sed 's|^\./||' | sort -u
}

find_test_pkgs() {
  find_test_dirs | xargs -n1 printf "${KUBE_GO_PACKAGE}/%s\n"
}

# -covermode=atomic becomes default with -race in Go >=1.3
KUBE_COVER=${KUBE_COVER:--cover -covermode=atomic}
KUBE_TIMEOUT=${KUBE_TIMEOUT:--timeout 30s}

cd "${KUBE_TARGET}"

usage() {
  cat << EOF
usage: $0 [OPTIONS] [TARGETS]

OPTIONS:
  -i <number>   : number of times to run each test, must be >= 1
EOF
}

isnum() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

iterations=1
while getopts "hi:" opt ; do
  case $opt in
    h)
      usage
      exit 0
      ;;
    i)
      iterations="$OPTARG"
      if ! isnum "${iterations}" || [[ "${iterations}" -le 0 ]]; then
        echo "$0": argument to -i must be numeric and greater than 0 >&2
        usage >&2
        exit 1
      fi
      ;;
    ?)
      usage >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG <value>" >&2
      usage >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND - 1))

# Use eval to preserve embedded quoted strings.
eval "goflags=(${GOFLAGS:-})"

if [[ "${iterations}" -gt 1 ]]; then
  if [[ $# -eq 0 ]]; then
    set -- $(find_test_dirs)
  fi
  echo "Running ${iterations} times"
  fails=0
  for arg; do
    trap 'exit 1' SIGINT
    echo
    pkg=${KUBE_GO_PACKAGE}/${arg}
    echo "${pkg}"
    # keep going, even if there are failures
    pass=0
    count=0
    for i in $(seq 1 ${iterations}); do
      if go test "${goflags[@]:+${goflags[@]}}" \
          -race ${KUBE_TIMEOUT} "${pkg}"; then
        pass=$((pass + 1))
      else
        fails=$((fails + 1))
      fi
      count=$((count + 1))
    done 2>&1
    echo "${pass}" / "${count}" passed
  done
  if [[ ${fails} -gt 0 ]]; then
    exit 1
  else
    exit 0
  fi
fi

if [[ -n "$1" ]]; then
  covdir="/tmp/k8s_coverage/$(date "+%s")"
  echo saving coverage output in "${covdir}"
  for arg; do
    trap 'exit 1' SIGINT
    mkdir -p "${covdir}/${arg}"
    pkg=${KUBE_GO_PACKAGE}/${arg}
    go test "${goflags[@]:+${goflags[@]}}" \
        -race \
        ${KUBE_TIMEOUT} \
        ${KUBE_COVER} -coverprofile="${covdir}/${arg}/coverage.out" \
        "${pkg}"
  done
  exit 0
fi

find_test_pkgs | xargs go test "${goflags[@]:+${goflags[@]}}" \
    -race \
    ${KUBE_TIMEOUT} \
    ${KUBE_COVER}
