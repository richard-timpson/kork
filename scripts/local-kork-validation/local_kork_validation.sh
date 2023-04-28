#!/bin/bash

set -e
set -o pipefail

function print_help() {
  echo "Usage: $0 [--skip-tests] [--skip-repos REPOS_TO_SKIP_CSV]"
  echo ""
  echo "This script builds kork and tests it against specified microservices."
  echo "By default, it will test against all microservices that use kork."
  echo ""
  echo "Options:"
  echo "  --skip-tests             Skip running tests during the builds."
  echo "  --skip-repos REPOS_TO_SKIP_CSV"
  echo "                           Skip testing against specified repositories,"
  echo "                           provide a comma-separated list of repository names."
  echo "  --help                   Show this help message and exit."
}

check_upstream() {
  local upstream_repo_url=$1
  local branch_name=$2

  echo "Checking that branch ${branch_name} is up to date with the latest commit from ${upstream_repo_url}"

  # Fetch the latest commit hash from the upstream remote branch
  local upstream_commit
  upstream_commit=$(git ls-remote "${upstream_repo_url}" "${branch_name}" | cut -f1)

  # Fetch the latest commit hash from the local branch
  local local_commit
  local_commit=$(git rev-parse "${branch_name}")

  # Compare the commit hashes and return the result
  if [ "$upstream_commit" == "$local_commit" ]; then
    return 0 # Local branch is up to date
  else
    return 1 # Local branch is not up to date
  fi
}

if [ "$1" == "--help" ]; then
  print_help
  exit 0
fi

# ANSI escape codes for colored text
RED='\033[0;31m'
NC='\033[0m' # No Color


# Set the kork version to be built and tested
kork_version="9.100.9-SNAPSHOT"

# Check if the skip arguments are passed
skip_tests=false
skip_repos=()

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --skip-tests)
    skip_tests=true
    shift
    ;;
    --skip-repos)
    IFS=',' read -ra skip_repos <<< "${2}"
    shift 2
    ;;
    *)
    echo "Unknown argument: ${1}"
    exit 1
    ;;
  esac
done

git_root=$(git rev-parse --show-toplevel)
spinnaker_root=$(dirname "$git_root")

# move to kork directory
pushd "$git_root"

# Build and publish the kork package locally
echo "Building kork..."
if ${skip_tests}; then
  # using --no-daemon in all gradle commands to avoid having a persistent java
  # process that is used for all builds. When the gradle daemon is used
  # with the persistent java process, that java process becomes completely blown up
  # and consumes a LOT of memory. When running local, it can cause jvm garbage collection/heap/memory
  # errors.
  ./gradlew --no-daemon build -x test
else
  ./gradlew --no-daemon build
fi
./gradlew --no-daemon -Pversion=${kork_version} publishToMavenLocal
echo "Kork build completed."

# Array containing the directories of the services that use kork
kork_services=("clouddriver" "echo" "fiat" "front50" "gate" "igor" "orca" "rosco")

# Iterate through each service and update the korkVersion in gradle.properties, then run the tests
for service in "${kork_services[@]}"; do
  skip_current_service=false

  # Check if the current service is in the skip_repos array
  for skip_repo in "${skip_repos[@]}"; do
    if [ "${service}" == "${skip_repo}" ]; then
      skip_current_service=true
      break
    fi
  done

  if ${skip_current_service}; then
    echo "Skipping service: ${service}"
  else
    echo "Processing service: ${service}"
    # move to the microservice directory
    pushd "$spinnaker_root/$service"

    branch_name="release-1.23.x-sfcd"
    upstream_repo="git@git.soma.salesforce.com:/spinnaker/${service}.git"

    # check if the repo is up to date with the upstream repo
    if check_upstream "${upstream_repo}" "${branch_name}"; then
      echo "Successfully validated git branch is up to date"
    else
      echo -e "${RED}########################################"
      echo -e "For ${service}, local branch ${branch_name} is not up to date with "
      echo -e "the latest upstream changes from ${upstream_repo}"
      echo -e "########################################${NC}"
      exit 1
    fi

    # Update the korkVersion in gradle.properties
    sed -i '' "s/^korkVersion=.*/korkVersion=${kork_version}/" "gradle.properties"

    # Test the service using the updated kork version
    echo "Building ${service}..."

    # Set the Gradle build command based on the skip_tests flag
    gradle_command="build --no-daemon"
    if ${skip_tests}; then
      gradle_command="build --no-daemon -x test"
    fi

    full_gradle_command="./gradlew ${gradle_command}"
    # Run the Gradle build command and check the result
    if $full_gradle_command; then
      echo "Build of ${service} completed."
    else
      echo -e "${RED}########################################"
      echo -e "# Build of ${service} failed.          #"
      echo -e "########################################${NC}"
      exit 1
    fi

    popd
  fi
done
