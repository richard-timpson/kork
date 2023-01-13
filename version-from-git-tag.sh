#!/usr/bin/env bash

set -e
set -o pipefail

# for debugging
set -x

# Write the version (if there is one) on stdout, in the form of two environment
# variable assignments.  One for gradle and one for bumpdeps.

# Don't emit a version on jenkins PR builds.  This prevents duplicate
# publishing.  In theory no one tags versions on PRs, but it does happen for
# testing.  Test scenarios that fire off branch builds can still make a mess,
# but we can only protect from so much.
#
# CHANGE_ID isn't documented at
# https://confluence.internal.salesforce.com/display/public/ZEN/SFCI+Managed+V2+-+Environment+Variables,
# but was the basis for determining PR builds in sfci-pipeline-sharedlib (see
# e.g. https://git.soma.salesforce.com/dci/sfci-pipeline-sharedlib/blob/1eb7490c8f30abe0a9591e3b8510d7bea3a0507f/src/net/sfdc/dci/v1/BuildUtilsImpl.groovy#L110-L112.
# and is present again in sfci-managed-preprocessor:
# https://git.soma.salesforce.com/sfci/sfci-managed-preprocessor/blob/a5d2afc6798220db4052f4dd81af3a4ffb434105/src/transformer/Util.js#L76
if [ -n "$CHANGE_ID" ]; then
  echo "ignoring version information in a PR build" >&2
  exit 0
fi

# Determine the version by looking at a git tag on the current commit
echo "current directory is '$PWD'" >&2
COMMIT_SHA=$(git rev-parse HEAD)

EXISTING_TAGS=$(git tag -l --points-at "$COMMIT_SHA")
echo "existingTags: '$EXISTING_TAGS'" >&2

# Find the tag(s) that indicate a version
#
# Use the { grep || :; } so let the script continue even if there's no release tag
#
# Don't include \([^[:space:]]\+\)\? to capture anything after the last digit
# (e.g. v1.2.3-foo, or v1.2.3foo, or v1.2.3-SNAPSHOT).
# This means we don't support tagging for snapshots.  We've lived for this long
# without, so let's keep the extra complexity out of the code.
RELEASE_TAGS=$(echo "$EXISTING_TAGS" | { grep --only-matching 'v[0-9]\+\.[0-9]\+\.[0-9]\+' || :; })
echo "RELEASE_TAGS is '$RELEASE_TAGS'" >&2

NUM_RELEASE_TAGS=$(echo "$RELEASE_TAGS" | wc -w | xargs)
if [ "$NUM_RELEASE_TAGS" -eq 0 ]; then
  echo "no release tag at current commit ($COMMIT_SHA), so version is unknown" >&2
  # This isn't a failure...Only that there's nothing to do.
  exit 0
fi

if [ "$NUM_RELEASE_TAGS" -gt 1 ]; then
  RELEASE_TAGS_ONELINE="${FILTERED_RELEASE_TAGS//$'\n'/ }"
  echo "more than one tag ($RELEASE_TAGS_ONELINE)...not sure which one to use" >&2
  # Let's leave this one as a failure since something likely really is wrong.
  exit 1
fi

# For readability, now that we know there's one tag.
VERSION=${RELEASE_TAGS}

# Strip the leading v to yield an actual version number.
STRIPPED_VERSION=${VERSION:1}

echo "ORG_GRADLE_PROJECT_version=${STRIPPED_VERSION}"
echo "BUMPDEPS_VERSION=${STRIPPED_VERSION}"
