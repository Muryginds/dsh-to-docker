ARG NODE_IMAGE=node:24-bookworm-slim

FROM ${NODE_IMAGE} AS deps
ARG DSH_VERSION=latest
ARG PNPM_VERSION=11
ARG NPM_REGISTRY=https://registry.npmjs.org/
RUN npm install --global --no-audit --no-fund --registry="${NPM_REGISTRY}" \
        "@deepseek-ai/dsh@${DSH_VERSION}" "pnpm@${PNPM_VERSION}" \
 && npm cache clean --force

FROM ${NODE_IMAGE}
ARG DSH_VERSION=latest
ARG TOOLSET=full
ARG EXTRA_APT_PACKAGES=
ARG VCS_REF=unknown
LABEL org.opencontainers.image.title="dsh" \
      org.opencontainers.image.description="DeepSeek Harness (dsh) web UI in a container" \
      org.opencontainers.image.version="${DSH_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="https://github.com/Muryginds/dsh-to-docker" \
      org.opencontainers.image.url="https://deepseek.com/harness" \
      org.opencontainers.image.licenses="MIT"
ENV DSH_HOME=/data/.dsh \
    DSH_AGENTS_HOME=/data/.agents \
    DSH_PORT=3080 \
    DSH_PROFILE=web
RUN case "${TOOLSET}" in \
        full|minimal) ;; \
        *) echo "TOOLSET must be full or minimal, got '${TOOLSET}'" >&2; exit 1 ;; \
    esac \
 && apt-get update \
 && apt-get install --yes --no-install-recommends \
        ca-certificates curl git jq openssh-client procps ripgrep tini unzip zip bubblewrap \
 && if [ "${TOOLSET}" = "full" ]; then \
        apt-get install --yes --no-install-recommends \
            build-essential python3 python3-pip python3-venv; \
    fi \
 && if [ -n "${EXTRA_APT_PACKAGES}" ]; then \
        apt-get install --yes --no-install-recommends ${EXTRA_APT_PACKAGES}; \
    fi \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*'
COPY --from=deps /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN node -e '\
  const fs = require("fs"), path = require("path");\
  const root = "/usr/local/lib/node_modules", binDir = "/usr/local/bin", dirs = [];\
  for (const entry of fs.readdirSync(root)) {\
    if (entry.startsWith("@")) for (const name of fs.readdirSync(path.join(root, entry))) dirs.push(`${entry}/${name}`);\
    else dirs.push(entry);\
  }\
  for (const dir of dirs) {\
    const pkg = path.join(root, dir);\
    const manifest = JSON.parse(fs.readFileSync(path.join(pkg, "package.json"), "utf8"));\
    const bins = typeof manifest.bin === "string" ? { [dir.split("/").pop()]: manifest.bin } : manifest.bin || {};\
    for (const [cmd, target] of Object.entries(bins)) {\
      const link = path.join(binDir, cmd);\
      fs.rmSync(link, { force: true });\
      fs.symlinkSync(path.relative(binDir, path.join(pkg, target)), link);\
    }\
  }\
'
COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN mkdir -p /data/.dsh /data/.agents /workspace \
 && chown --recursive node:node /data /workspace
USER node
WORKDIR /workspace
EXPOSE 3080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["/usr/local/bin/docker-entrypoint.sh", "healthcheck"]
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["web"]
