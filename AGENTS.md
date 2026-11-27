# AGENTS.md

## What this repo is

Packaging of the npm package `@deepseek-ai/dsh` (DeepSeek Harness) as a Docker image. The dsh source is not here (upstream: https://github.com/deepseek-ai/deepseek-harness). There is no app code, `node_modules`, linter or test suite; changes are verified with the build scripts and by running the image.

## Verify changes

- `bash -n scripts/*.sh docker-entrypoint.sh`
- `./scripts/build.sh --dry-run` and `./scripts/publish.sh --dry-run --yes` print the docker commands and need no Docker; combine with `--version`, `--toolset minimal`, `--platforms linux/amd64,linux/arm64`, bad values (validation paths) to cover variants.
- Prompts appear only when stdin and stdout are TTYs. Agent shells are not TTYs, so the scripts silently use defaults and `publish.sh` needs `--yes`; to exercise the prompts use `expect`.
- With Docker running: `./scripts/build.sh --version <v>` loads the image and runs `dsh --version`; on an Apple Silicon Mac add `--platforms linux/arm64` for a native build (a `linux/amd64` build is emulated, and the smoke test only warns when emulation is unavailable).
- Inspect the image with `docker run --rm --entrypoint sh <image> -c '...'`: the entrypoint forwards every command to `dsh`, so without `--entrypoint` a shell command is parsed as a dsh command. The package dir is root-owned; run node probes with `cd` into it and `--input-type=module -e`, not by writing files.
- Check entry ids and flags of the installed version with `docker run --rm <image> --profile web --dump-default-config` and `docker run --rm <image> web --help` (the latter boots part of the tree, ~2.5 s).
- Runtime check: `docker run -d -p 3080:3080 -v <vol>:/data <image>`, wait for a `token=` line in `docker logs`, then `curl` the URL with a cookie jar (expect 303, then 200 on `/`; `/api/*` under a foreign `Host` gives 403).
- `docker compose` needs `.env` to exist (`cp .env.example .env`) and `DSH_TAG` pointing at a tag that exists locally; never commit `.env` (holds `DEEPSEEK_API_KEY` / `ORG_PROXY_API_KEY`).
- Never run `publish.sh` without `--dry-run` as a test: with `--yes --allow-dirty` nothing stops it before the push.
- Model calls, a custom provider and the bash tool can be exercised without a real key: run a mock OpenAI-compatible server container on a docker network (streaming `POST /v1/chat/completions`, `GET /v1/models`), mount a home-level `cordis.patch.yml` (row `llm-pi-ai`, `providers.<name>` with `api`, `baseURL: !!js process.env.ORG_PROXY_BASE_URL`, `models`) at `/data/.dsh/cordis.patch.yml`, and run `dsh --patch <overlay whose row agent-default-model names the provider and model> --profile headless "..."` with `DSH_PERMISSION_MODE=danger-full-access`, the `apiKeyEnv` variable and `ORG_PROXY_BASE_URL` set. Let the mock answer the first tool-bearing request with a `bash` tool call (`description` and `command` are both required); the command's output arrives in the next request's `tool` message.
- `docker compose exec` starts with the container's original environment, not the entrypoint's exports; pass `-e DSH_PERMISSION_MODE=...` when running headless inside a running service.
- Upstream is a developer preview with breaking changes: confirm flags, env vars and config ids against the installed version or the upstream docs before changing `docker-entrypoint.sh`, `.env.example` or `cordis.patch.example.yml`.

## Constraints

- Scripts run on macOS default `/bin/bash` 3.2 and in WSL bash 5: no associative arrays, `mapfile`, `${var,,}`, `local -n`; guard possibly empty arrays under `set -u` with `${arr[@]+"${arr[@]}"}`. Shell scripts carry no comments; user-facing text is in `--help`, `README.md` and `.env.example`.
- `.gitattributes` forces LF (the repo is also used from Windows + WSL): shebang scripts must stay LF and executable; the Dockerfile relies on `COPY --chmod=0755`.
- `.dockerignore` is an allowlist (`*`, then `!Dockerfile`, `!docker-entrypoint.sh`): any new file the build needs must be added there.
- `COPY --from` of a single symlink dereferences it (the `dsh` launcher then breaks on relative imports), and copying the whole `/usr/local/bin` duplicates the 118 MB `node` binary. The Dockerfile therefore regenerates bin symlinks from the packages' `bin` fields and must overwrite the base image's `pnpm`/`pnpx` Corepack shims, which would otherwise download pnpm 12 at runtime.
- npm 11 in the base image skips dependency install scripts by default (`allow-scripts` policy). Verified harmless on Linux for 0.2.2-rc.5 (koffi loads from its `@koromix/*` platform packages, node-pty's `spawn-helper` is darwin-only); re-check if a native feature breaks after bumping the base image or dsh.
- Most of the image size is dsh's own npm payload (sources, maps, wasm); do not strip it — the `dsh-doc` skill reads the installed source.
- `dsh web --host` rejects wildcard addresses, so `docker-entrypoint.sh` detects the container IP; `--no-open` is mandatory (no browser); `DSH_TRUSTED_HOSTS` becomes repeated `--trusted-host` (the fence applies to `/api`, not to `/` or the token exchange).
- `docker-entrypoint.sh` probes bwrap and Landlock and, when neither works and `DSH_PERMISSION_MODE` is unset, exports `danger-full-access` with a warning. `probe()` from `@deepseek-ai/node-addon-system/landlock-run` returns a plain string synchronously. Docker Desktop's VM kernel has no Landlock (`/sys/kernel/security/lsm` is `capability,yama`) and bwrap needs `--privileged`.
- dsh rejects an empty `DSH_PERMISSION_MODE` (22 plugins stay inactive and the bash/fs tools vanish), so the entrypoint unsets an empty value. The variable decides the preset fresh sessions start from (`danger-full-access` runs commands unconfined; `--permission-mode` does the same for headless).
- `examples/openai-proxy/` is a template directory: `*.example.*` files are tracked, the copies users create (`.env`, `cordis.patch.yml`, `workspace/`) are gitignored at any depth. The step-by-step guide is `examples/openai-proxy/README.md`; the root README links to it instead of repeating the OpenAI setup.
- `examples/openai-proxy/cordis.patch.example.yml` takes the endpoint from `ORG_PROXY_BASE_URL` (`baseURL: !!js process.env.ORG_PROXY_BASE_URL`); keep internal addresses out of tracked files and pass them through `.env`.
- `DSH_PERMISSION_MODE` and other upstream env vars are read in bundle YAML (`!!js` expressions in `cordis.patch.yml`), not in JS; grep `*.yml` too when checking what a version supports.
- Any entrypoint command other than `web`/`healthcheck` passes straight to `dsh` (`docker run <image> --version`, `headless "task"`).
- Tag scheme: `publish.sh` (`compute_publish_tags` in `scripts/common.sh`) pushes an immutable `<version>[-<toolset>]-r<N>` and moves the aliases `<version>[-<toolset>]` plus one per npm dist-tag pointing at that version; `next_free_revision` probes the registry, an existing `-r<N>` needs `--overwrite`, an uncommitted tree needs `--allow-dirty`, and the git commit travels as `VCS_REF` into the `org.opencontainers.image.revision` label. `build.sh` only tags aliases locally. Dist-tags come from `${NPM_REGISTRY%/}/-/package/@deepseek-ai/dsh/dist-tags`.
- Multi-platform pushes need a `docker-container` buildx builder: the script creates `dsh-builder` on demand and selects it with `--builder`, leaving the global default builder alone. `--load` works for a single platform only, which is why `build.sh` and `publish.sh` are separate.
- `docker buildx imagetools inspect` prints `Platform:` lines only for multi-arch indexes; `manifest_platforms` in `scripts/common.sh` reads both shapes (`--raw` for indexes, `--format '{{.Image.OS}}/{{.Image.Architecture}}'` for a single manifest).
- `require_login` asks the credential helper (`docker-credential-desktop list`) whether the store is empty, so `publish.sh` fails before building when only `credsStore` is set in `~/.docker/config.json`.
- `NODE_ENV` is deliberately not set in the image (it would make the agent's own `npm install` skip devDependencies).
- README and `.env.example` are written in Russian; script output is English.
