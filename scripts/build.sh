#!/usr/bin/env bash
set -euo pipefail

DEFAULT_PLATFORMS="linux/amd64"
OUTPUT_MODE="--load"
SMOKE_PULL=0

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/build.sh [options]

Build the dsh image locally (buildx --load, one platform). Nothing is pushed;
use scripts/publish.sh for a multi-platform release.

Options:
  --version <version|dist-tag>  npm dist-tag (latest, next, alpha) or an exact
                                version such as 0.2.2-rc.5; default: latest
  --toolset <full|minimal>      apt toolset baked into the image; default: full
  --platforms <list>            comma-separated; only the first entry is built;
                                default: linux/amd64
  --image <namespace/name>      default: muryginds/dsh
  --extra-packages <list>       space-separated apt packages to add
  --node-image <image>          base image; default: node:24-bookworm-slim
  --npm-registry <url>          registry to install dsh from; default: https://registry.npmjs.org/
  --pull                        fetch the base image before building
  --no-cache                    build without cache
  --no-smoke                    skip the 'dsh --version' check
  --yes, -y                     accept the defaults, do not ask
  --dry-run                     print the docker commands without running them
  -h, --help

Options may also come from the environment: DSH_VERSION, DSH_TOOLSET,
DSH_PLATFORMS, DSH_IMAGE, DSH_EXTRA_APT_PACKAGES, DSH_NODE_IMAGE, DSH_NPM_REGISTRY.
On a terminal and without --yes the script asks for release, toolset, platforms
and extra packages.
EOF
}

main() {
  parse_args "$@"
  resolve_release
  prompt_toolset
  prompt_platforms
  prompt_extra_packages
  IMAGE="${IMAGE:-muryginds/dsh}"
  normalize_platforms
  validate_inputs
  if [ "$(platform_count)" -gt 1 ]; then
    PLATFORMS="${PLATFORMS%%,*}"
    warn "local builds take one platform; building ${PLATFORMS}, use scripts/publish.sh for more"
  fi
  compute_tags
  print_summary
  if is_interactive && [ "${ASSUME_YES}" != "1" ]; then
    confirm "Build now?" || exit 1
  fi
  build_cmd "${IMAGE_TAGS[0]}"
  run "${BUILD_CMD[@]}"
  smoke_test
  info "done: ${IMAGE_TAGS[0]}"
  info "try:   docker run --rm --name dsh -p 3080:3080 -v dsh-data:/data ${IMAGE_TAGS[0]}"
}

main "$@"
