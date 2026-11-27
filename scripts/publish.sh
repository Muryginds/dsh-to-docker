#!/usr/bin/env bash
set -euo pipefail

DEFAULT_PLATFORMS="linux/amd64"
OUTPUT_MODE="--push"
SMOKE_PULL=1

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/publish.sh [options]

Build the dsh image and push it to a registry. Every publish creates a new
immutable tag <version>[-<toolset>]-r<N> and moves the aliases to it:
<version>[-<toolset>] plus one per npm dist-tag that points to that version
(latest, next, alpha). An existing -r<N> tag is never overwritten unless
--overwrite is given, and the tree must be committed unless --allow-dirty is.

Options:
  --version <version|dist-tag>  npm dist-tag (latest, next, alpha) or an exact
                                version such as 0.2.2-rc.5; default: latest
  --toolset <full|minimal>      apt toolset baked into the image; default: full
  --platforms <list>            comma-separated, e.g. linux/amd64,linux/arm64;
                                default: linux/amd64
  --image <namespace/name>      default: muryginds/dsh
  --revision <n>                revision number for the immutable tag; default:
                                the next free one in the registry
  --extra-packages <list>       space-separated apt packages to add
  --node-image <image>          base image; default: node:24-bookworm-slim
  --npm-registry <url>          registry to install dsh from; default: https://registry.npmjs.org/
  --builder <name>              buildx builder used for multi-platform builds;
                                created on demand; default: dsh-builder
  --overwrite                   allow replacing an existing -r<N> tag
  --allow-dirty                 allow building from an uncommitted git tree
  --no-cache                    build without cache
  --no-smoke                    skip pulling the image back and running 'dsh --version'
  --yes, -y                     accept the defaults, do not ask or confirm
  --dry-run                     print the docker commands without running them
  -h, --help

Options may also come from the environment: DSH_VERSION, DSH_TOOLSET,
DSH_PLATFORMS, DSH_IMAGE, DSH_REVISION, DSH_EXTRA_APT_PACKAGES, DSH_NODE_IMAGE,
DSH_NPM_REGISTRY. Requires 'docker login' for the target registry. On a terminal
and without --yes the script asks for release, toolset, platforms, extra
packages, image name and revision. The image label
org.opencontainers.image.revision carries the git commit it was built from.
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
  resolve_vcs_ref
  resolve_revision
  compute_publish_tags
  print_summary
  ensure_builder
  confirm "Push ${IMAGE_TAGS[0]} and move the alias tags to it?"
  require_login
  build_cmd "${IMAGE_TAGS[@]}"
  run "${BUILD_CMD[@]}"
  verify_manifest
  smoke_test
  info "done: ${IMAGE_TAGS[0]}"
}

main "$@"
