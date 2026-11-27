#!/usr/bin/env bash
set -euo pipefail

DEFAULT_PLATFORMS="linux/amd64"
OUTPUT_MODE="--push"
SMOKE_PULL=1

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/publish.sh [options]

Build the dsh image and push it to a registry. Every tag is pushed:
<version>, plus one tag per npm dist-tag that points to it (latest, next, alpha);
a non-full toolset gets a -<toolset> suffix (e.g. latest-minimal).

Options:
  --version <version|dist-tag>  npm dist-tag (latest, next, alpha) or an exact
                                version such as 0.2.2-rc.5; default: latest
  --toolset <full|minimal>      apt toolset baked into the image; default: full
  --platforms <list>            comma-separated, e.g. linux/amd64,linux/arm64;
                                default: linux/amd64
  --image <namespace/name>      default: muryginds/dsh
  --extra-packages <list>       space-separated apt packages to add
  --node-image <image>          base image; default: node:24-bookworm-slim
  --npm-registry <url>          registry to install dsh from; default: https://registry.npmjs.org/
  --builder <name>              buildx builder used for multi-platform builds;
                                created on demand; default: dsh-builder
  --no-cache                    build without cache
  --no-smoke                    skip pulling the image back and running 'dsh --version'
  --yes, -y                     accept the defaults, do not ask or confirm
  --dry-run                     print the docker commands without running them
  -h, --help

Options may also come from the environment: DSH_VERSION, DSH_TOOLSET,
DSH_PLATFORMS, DSH_IMAGE, DSH_EXTRA_APT_PACKAGES, DSH_NODE_IMAGE, DSH_NPM_REGISTRY.
Requires 'docker login' for the target registry. On a terminal and without --yes
the script asks for release, toolset, platforms, extra packages and the image name.
EOF
}

main() {
  parse_args "$@"
  resolve_release
  prompt_toolset
  prompt_platforms
  prompt_extra_packages
  ask IMAGE "image (namespace/name)" "muryginds/dsh"
  normalize_platforms
  validate_inputs
  compute_tags
  print_summary
  ensure_builder
  confirm "Push ${IMAGE_TAGS[0]} to the registry?"
  require_login
  build_cmd "${IMAGE_TAGS[@]}"
  run "${BUILD_CMD[@]}"
  verify_manifest
  smoke_test
  info "done: ${IMAGE_TAGS[0]}"
}

main "$@"
