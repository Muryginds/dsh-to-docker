#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"

IMAGE="${DSH_IMAGE:-}"
RELEASE="${DSH_VERSION:-}"
RELEASE_SET=0
TOOLSET="${DSH_TOOLSET:-}"
PLATFORMS="${DSH_PLATFORMS:-}"
EXTRA_APT_PACKAGES="${DSH_EXTRA_APT_PACKAGES:-}"
NODE_IMAGE="${DSH_NODE_IMAGE:-}"
NPM_REGISTRY="${DSH_NPM_REGISTRY:-https://registry.npmjs.org/}"
BUILDER_NAME="${DSH_BUILDER:-dsh-builder}"
NO_CACHE=0
PULL=0
ASSUME_YES=0
DRY_RUN=0
NO_SMOKE=0
VERSION=""
CHANNEL=""
DIST_TAGS=""
BUILDER=""
IMAGE_TAGS=()
BUILD_CMD=()

VALUE_OPTIONS=" --version --toolset --platforms --image --extra-packages --node-image --npm-registry --builder "

info() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

is_interactive() {
  [ -t 0 ] && [ -t 1 ]
}

ask() {
  local var="$1" prompt="$2" default="$3" input=""
  if [ -z "${!var:-}" ] && [ "${ASSUME_YES}" != "1" ] && is_interactive; then
    if [ -n "${default}" ]; then
      read -r -p "${prompt} [${default}]: " input || true
    else
      read -r -p "${prompt}: " input || true
    fi
  fi
  printf -v "${var}" '%s' "${input:-${!var:-${default}}}"
}

confirm() {
  local answer=""
  if [ "${ASSUME_YES}" = "1" ]; then
    return 0
  fi
  if ! is_interactive; then
    die "$1 (re-run with --yes or -y to skip this confirmation)"
  fi
  read -r -p "$1 [y/N]: " answer || true
  case "${answer}" in
    [Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

set_value_option() {
  case "$1" in
    --image) IMAGE="$2" ;;
    --version) RELEASE="$2"; RELEASE_SET=1 ;;
    --toolset) TOOLSET="$2" ;;
    --platforms) PLATFORMS="$2" ;;
    --extra-packages) EXTRA_APT_PACKAGES="$2" ;;
    --node-image) NODE_IMAGE="$2" ;;
    --npm-registry) NPM_REGISTRY="$2" ;;
    --builder) BUILDER_NAME="$2" ;;
  esac
  if [ "$1" = "--version" ] && [ -z "$2" ]; then
    RELEASE_SET=0
  fi
}

is_value_option() {
  case " ${VALUE_OPTIONS} " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

parse_args() {
  local opt val
  while [ "$#" -gt 0 ]; do
    opt="$1"
    val=""
    case "${opt}" in
      --*=*)
        val="${opt#*=}"
        opt="${opt%%=*}"
        ;;
    esac
    if is_value_option "${opt}"; then
      if [ -z "${val}" ]; then
        [ "$#" -ge 2 ] || die "option ${opt} requires a value (see --help)"
        val="$2"
        shift
      fi
      set_value_option "${opt}" "${val}"
      shift
      continue
    fi
    case "${opt}" in
      --no-cache) NO_CACHE=1 ;;
      --pull) PULL=1 ;;
      --no-smoke) NO_SMOKE=1 ;;
      --yes|-y) ASSUME_YES=1 ;;
      --dry-run) DRY_RUN=1 ;;
      -h|--help)
        usage
        exit 0
        ;;
      *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
  done
}

validate_inputs() {
  case "${TOOLSET}" in
    full|minimal) ;;
    *) die "toolset must be 'full' or 'minimal', got '${TOOLSET}'" ;;
  esac
  local p
  for p in $(printf '%s' "${PLATFORMS}" | tr ',' ' '); do
    case "${p}" in
      linux/*) ;;
      *) die "platforms must be linux/<arch> entries, got '${p}'" ;;
    esac
  done
  case "${IMAGE}" in
    */*) ;;
    *) die "image must look like namespace/name, got '${IMAGE}'" ;;
  esac
  case "${IMAGE}" in
    *[!a-z0-9._/-]*|*:*|*@*)
      die "image must be lowercase namespace/name without a tag or digest, got '${IMAGE}'"
      ;;
  esac
  if [ -n "${EXTRA_APT_PACKAGES}" ]; then
    printf '%s\n' "${EXTRA_APT_PACKAGES}" \
      | grep -Eq '^[A-Za-z0-9][A-Za-z0-9.+-]*( +[A-Za-z0-9][A-Za-z0-9.+-]*)*$' \
      || die "extra packages must be space-separated apt package names"
  fi
  case "${VERSION}" in
    "") die "could not resolve the dsh version" ;;
  esac
}

fetch_dist_tags() {
  local url json
  url="${NPM_REGISTRY%/}/-/package/@deepseek-ai/dsh/dist-tags"
  if ! json="$(curl --fail --silent --show-error --location --max-time 30 "${url}")"; then
    DIST_TAGS=""
    return 1
  fi
  if command -v jq >/dev/null 2>&1; then
    DIST_TAGS="$(jq -r 'to_entries[] | "\(.key)=\(.value)"' <<< "${json}")"
  else
    DIST_TAGS="$(printf '%s' "${json}" | tr ',' '\n' | sed -nE 's/.*"([^"]+)":"([^"]+)".*/\1=\2/p')"
  fi
  [ -n "${DIST_TAGS}" ]
}

print_dist_tags() {
  if [ -n "${DIST_TAGS}" ]; then
    info "npm dist-tags: $(printf '%s' "${DIST_TAGS}" | tr '\n' ' ')"
  fi
}

dist_tag_key() {
  local line
  while IFS= read -r line; do
    if [ "${line%%=*}" = "$1" ]; then
      printf '%s' "${line%%=*}"
      return 0
    fi
  done <<< "${DIST_TAGS}"
  return 1
}

dist_tag_value() {
  local line
  while IFS= read -r line; do
    if [ "${line%%=*}" = "$1" ]; then
      printf '%s' "${line#*=}"
      return 0
    fi
  done <<< "${DIST_TAGS}"
  return 1
}

resolve_release() {
  if [ -z "${DIST_TAGS}" ]; then
    fetch_dist_tags || warn "npm registry ${NPM_REGISTRY} is unreachable; dist-tags are unavailable"
  fi
  if [ "${RELEASE_SET}" != "1" ]; then
    print_dist_tags
    ask RELEASE "dsh release (dist-tag or exact version)" "latest"
  fi
  if CHANNEL="$(dist_tag_key "${RELEASE}")"; then
    VERSION="$(dist_tag_value "${CHANNEL}")"
  else
    case "${RELEASE}" in
      [0-9]*) VERSION="${RELEASE}" ;;
      *)
        die "'${RELEASE}' is neither a known dist-tag nor an exact version (dist-tags: $(printf '%s\n' "${DIST_TAGS}" | cut -d= -f1 | tr '\n' ' '))"
        ;;
    esac
  fi
}

prompt_toolset() {
  ask TOOLSET "toolset: full (git, python3, build-essential, ...) or minimal" "full"
}

prompt_platforms() {
  ask PLATFORMS "platforms (comma-separated, e.g. linux/amd64,linux/arm64)" "${DEFAULT_PLATFORMS}"
}

prompt_extra_packages() {
  ask EXTRA_APT_PACKAGES "extra apt packages (space-separated, empty = none)" ""
}

normalize_platforms() {
  local out="" p
  for p in $(printf '%s' "${PLATFORMS}" | tr ',' ' ' | tr 'A-Z' 'a-z'); do
    out="${out:+${out},}${p}"
  done
  PLATFORMS="${out}"
  [ -n "${PLATFORMS}" ] || die "no platforms given"
}

platform_count() {
  printf '%s' "${PLATFORMS}" | tr ',' '\n' | grep -c '[^[:space:]]'
}

compute_tags() {
  local suffix="" line
  [ "${TOOLSET}" = "full" ] || suffix="-${TOOLSET}"
  IMAGE_TAGS=("${IMAGE}:${VERSION}${suffix}")
  if [ -z "${DIST_TAGS}" ]; then
    fetch_dist_tags || { warn "dist-tags are unavailable; using only the version tag"; return 0; }
  fi
  while IFS= read -r line; do
    if [ -n "${line}" ] && [ "${line#*=}" = "${VERSION}" ]; then
      IMAGE_TAGS+=("${IMAGE}:${line%%=*}${suffix}")
    fi
  done <<< "${DIST_TAGS}"
}

print_summary() {
  local tags
  tags="$(printf '%s, ' "${IMAGE_TAGS[@]}")"
  info "Image:      ${IMAGE}"
  info "Version:    ${VERSION}"
  info "Toolset:    ${TOOLSET}"
  info "Platforms:  ${PLATFORMS}"
  info "Extra apt:  ${EXTRA_APT_PACKAGES:-none}"
  info "Tags:       ${tags%, }"
}

ensure_builder() {
  BUILDER=""
  if [ "$(platform_count)" -le 1 ]; then
    return 0
  fi
  if [ "${DRY_RUN}" = "1" ]; then
    info "dry-run: multi-platform builds need a docker-container builder"
    return 0
  fi
  if docker buildx inspect "${BUILDER_NAME}" >/dev/null 2>&1; then
    BUILDER="${BUILDER_NAME}"
    return 0
  fi
  if docker buildx inspect --bootstrap 2>/dev/null | grep -q 'docker-container'; then
    return 0
  fi
  info "creating buildx builder '${BUILDER_NAME}' for the multi-platform build"
  docker buildx create --name "${BUILDER_NAME}" --driver docker-container >/dev/null
  BUILDER="${BUILDER_NAME}"
}

build_cmd() {
  BUILD_CMD=(buildx build --platform "${PLATFORMS}")
  if [ -n "${BUILDER}" ]; then
    BUILD_CMD+=(--builder "${BUILDER}")
  fi
  BUILD_CMD+=(--build-arg "DSH_VERSION=${VERSION}")
  BUILD_CMD+=(--build-arg "TOOLSET=${TOOLSET}")
  BUILD_CMD+=(--build-arg "NPM_REGISTRY=${NPM_REGISTRY}")
  if [ -n "${EXTRA_APT_PACKAGES}" ]; then
    BUILD_CMD+=(--build-arg "EXTRA_APT_PACKAGES=${EXTRA_APT_PACKAGES}")
  fi
  if [ -n "${NODE_IMAGE}" ]; then
    BUILD_CMD+=(--build-arg "NODE_IMAGE=${NODE_IMAGE}")
  fi
  if [ "${NO_CACHE}" = "1" ]; then
    BUILD_CMD+=(--no-cache)
  fi
  if [ "${PULL}" = "1" ]; then
    BUILD_CMD+=(--pull)
  fi
  local tag
  for tag in "$@"; do
    BUILD_CMD+=(-t "${tag}")
  done
  BUILD_CMD+=("${OUTPUT_MODE}" "${ROOT_DIR}")
}

run() {
  if [ "${DRY_RUN}" = "1" ]; then
    printf '  docker'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  docker "$@"
}

native_platform() {
  local arch
  arch="$(docker version --format '{{.Server.Arch}}' 2>/dev/null)" || return 1
  case "${arch}" in
    amd64|arm64|arm|386|ppc64le|s390x|riscv64) printf 'linux/%s' "${arch}" ;;
    *) return 1 ;;
  esac
}

smoke_test() {
  local ref="${IMAGE_TAGS[0]}" native out
  if [ "${NO_SMOKE}" = "1" ]; then
    return 0
  fi
  if [ "${DRY_RUN}" = "1" ]; then
    run run --rm "${ref}" dsh --version
    return 0
  fi
  native="$(native_platform)" || { warn "cannot detect the local platform; skipping the smoke test"; return 0; }
  case ",${PLATFORMS}," in
    *",${native},"*) ;;
    *) warn "${native} was not built; skipping the smoke test"; return 0 ;;
  esac
  if [ "${SMOKE_PULL}" = "1" ]; then
    run pull --platform "${native}" "${ref}" || die "cannot pull ${ref}"
  fi
  if ! out="$(docker run --rm --platform "${native}" "${ref}" dsh --version 2>&1)"; then
    printf '%s\n' "${out}" >&2
    die "smoke test failed: 'dsh --version' returned an error"
  fi
  info "dsh --version: ${out}"
  case "${out}" in
    *"${VERSION}"*) ;;
    *) die "smoke test failed: expected version ${VERSION}" ;;
  esac
}

require_login() {
  if [ "${DRY_RUN}" = "1" ]; then
    return 0
  fi
  local cfg="${DOCKER_CONFIG:-${HOME}/.docker}/config.json" store helper entries
  if [ ! -f "${cfg}" ]; then
    die "Docker Hub credentials not found; run 'docker login' first"
  fi
  if tr -d '\n ' < "${cfg}" | grep -Eq '"index\.docker\.io[^"]*":\{"auth"'; then
    return 0
  fi
  store="$(sed -n 's/.*"credsStore": *"\([^"]*\)".*/\1/p' "${cfg}" | head -1)"
  helper="docker-credential-${store}"
  if [ -n "${store}" ] && command -v "${helper}" >/dev/null 2>&1; then
    entries="$("${helper}" list 2>/dev/null | tr -d '{}" \n' || true)"
    if [ -n "${entries}" ]; then
      return 0
    fi
    die "the '${store}' credential store has no registry login; run 'docker login' first"
  fi
  grep -Eq '"(index\.docker\.io[^"]*|credsStore|credHelpers)"' "${cfg}" \
    || die "Docker Hub credentials not found; run 'docker login' first"
}

verify_manifest() {
  local manifest p
  if [ "${DRY_RUN}" = "1" ]; then
    run buildx imagetools inspect "${IMAGE_TAGS[0]}"
    return 0
  fi
  manifest="$(docker buildx imagetools inspect "${IMAGE_TAGS[0]}")" \
    || die "cannot inspect ${IMAGE_TAGS[0]} in the registry"
  for p in $(printf '%s' "${PLATFORMS}" | tr ',' ' '); do
    if printf '%s\n' "${manifest}" | grep -Eq "Platform:[[:space:]]+${p}\$"; then
      info "published:  ${p}"
    else
      warn "${p} is missing from the manifest of ${IMAGE_TAGS[0]}"
    fi
  done
}
