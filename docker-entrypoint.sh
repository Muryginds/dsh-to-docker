#!/usr/bin/env bash
set -euo pipefail

DSH_HOME="${DSH_HOME:-${HOME}/.dsh}"
DSH_AGENTS_HOME="${DSH_AGENTS_HOME:-${HOME}/.agents}"
DSH_PROFILE="${DSH_PROFILE:-web}"
DSH_PORT="${DSH_PORT:-3080}"
HOST_FILE="${HOST_FILE:-/tmp/dsh-host}"

log() {
  printf 'dsh-docker: %s\n' "$*" >&2
}

die() {
  log "$*"
  exit 1
}

detect_host() {
  local host
  host="$(node -e '
    const os = require("os")
    const ifaces = os.networkInterfaces()
    const first = (family) => {
      for (const name of Object.keys(ifaces).sort()) {
        for (const item of ifaces[name] || []) {
          if (item.family === family && !item.internal) return item.address
        }
      }
      return ""
    }
    process.stdout.write(first("IPv4") || first("IPv6"))
  ' 2>/dev/null || true)"
  if [ -z "${host}" ]; then
    host="$(hostname -i 2>/dev/null | awk '{print $1}' || true)"
  fi
  if [ -z "${host}" ]; then
    host="127.0.0.1"
    log "container IP not detected, falling back to 127.0.0.1"
  fi
  printf '%s' "${host}"
}

ensure_writable() {
  local dir
  for dir in "${DSH_HOME}" "${DSH_AGENTS_HOME}"; do
    if ! mkdir -p "${dir}" 2>/dev/null || [ ! -w "${dir}" ]; then
      log "WARNING: ${dir} is not writable by uid $(id -u); mount a writable volume there"
    fi
  done
  if [ ! -w "${PWD}" ]; then
    log "WARNING: workspace ${PWD} is not writable by uid $(id -u)"
  fi
}

web_args() {
  WEB_ARGS=(--profile "${DSH_PROFILE}" --no-open --host "${BIND_HOST}" --port "${DSH_PORT}")
  local public_url="${DSH_PUBLIC_URL-http://localhost:${DSH_PORT}/}"
  if [ -n "${public_url}" ] && [ "${public_url}" != "none" ]; then
    WEB_ARGS+=(--public-url "${public_url}")
  fi
  local entry
  for entry in $(printf '%s' "${DSH_TRUSTED_HOSTS:-}" | tr ',' ' '); do
    WEB_ARGS+=(--trusted-host "${entry}")
  done
  if [ -n "${DSH_TLS_CERT:-}" ] && [ -n "${DSH_TLS_KEY:-}" ]; then
    WEB_ARGS+=(--tls-cert "${DSH_TLS_CERT}" --tls-key "${DSH_TLS_KEY}")
  elif [ -n "${DSH_TLS_CERT:-}" ] || [ -n "${DSH_TLS_KEY:-}" ]; then
    die "DSH_TLS_CERT and DSH_TLS_KEY must be set together"
  fi
  for entry in ${DSH_EXTRA_ARGS:-}; do
    WEB_ARGS+=("${entry}")
  done
}

healthcheck() {
  local host port scheme
  host="$(cat "${HOST_FILE}" 2>/dev/null || true)"
  [ -n "${host}" ] || host="$(detect_host)"
  case "${host}" in
    *:*) host="[${host}]" ;;
  esac
  port="${DSH_PORT}"
  scheme="http"
  if [ -n "${DSH_TLS_CERT:-}" ]; then
    scheme="https"
  fi
  curl --insecure --silent --output /dev/null --max-time 4 "${scheme}://${host}:${port}/"
}

case "${1:-web}" in
  web)
    shift || true
    ensure_writable
    BIND_HOST="${DSH_HOST:-$(detect_host)}"
    printf '%s\n' "${BIND_HOST}" > "${HOST_FILE}"
    web_args
    log "profile=${DSH_PROFILE} host=${BIND_HOST} port=${DSH_PORT} home=${DSH_HOME}"
    exec dsh "${WEB_ARGS[@]}" "$@"
    ;;
  healthcheck)
    healthcheck
    ;;
  *)
    exec dsh "$@"
    ;;
esac
