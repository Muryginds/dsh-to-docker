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
- `docker compose` needs `.env` to exist (`cp .env.example .env`) and `DSH_TAG` pointing at a tag that exists locally; never commit `.env` (holds `DEEPSEEK_API_KEY`).
- Model calls and the bash tool in a real session need an API key and are not covered by any automated check here.
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
- `DSH_PERMISSION_MODE` and other upstream env vars are read in bundle YAML (`!!js` expressions in `cordis.patch.yml`), not in JS; grep `*.yml` too when checking what a version supports.
- Any entrypoint command other than `web`/`healthcheck` passes straight to `dsh` (`docker run <image> --version`, `headless "task"`).
- Tag scheme is `compute_tags` in `scripts/common.sh`: `<version>` plus one tag per npm dist-tag that points to it; a non-`full` toolset gets a `-<toolset>` suffix. Dist-tags come from `${NPM_REGISTRY%/}/-/package/@deepseek-ai/dsh/dist-tags`.
- Multi-platform pushes need a `docker-container` buildx builder: the script creates `dsh-builder` on demand and selects it with `--builder`, leaving the global default builder alone. `--load` works for a single platform only, which is why `build.sh` and `publish.sh` are separate.
- `docker buildx imagetools inspect` prints `Platform:` lines only for multi-arch indexes; `manifest_platforms` in `scripts/common.sh` reads both shapes (`--raw` for indexes, `--format '{{.Image.OS}}/{{.Image.Architecture}}'` for a single manifest).
- `require_login` asks the credential helper (`docker-credential-desktop list`) whether the store is empty, so `publish.sh` fails before building when only `credsStore` is set in `~/.docker/config.json`.
- `NODE_ENV` is deliberately not set in the image (it would make the agent's own `npm install` skip devDependencies).
- README and `.env.example` are written in Russian; script output is English.
