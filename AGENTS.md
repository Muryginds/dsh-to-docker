# AGENTS.md

## What this repo is

Packaging of the npm package `@deepseek-ai/dsh` (DeepSeek Harness) as a Docker image. The dsh source is not here (upstream: https://github.com/deepseek-ai/deepseek-harness). There is no app code, `node_modules`, linter or test suite; changes are verified with the build scripts and by running the image.

## Verify changes

- `bash -n scripts/*.sh docker-entrypoint.sh`
- `./scripts/build.sh --dry-run` and `./scripts/publish.sh --dry-run --yes` print the docker commands and need no Docker; combine with `--version`, `--toolset minimal`, `--platforms linux/amd64,linux/arm64`, bad values (validation paths) to cover variants.
- Prompts appear only when stdin and stdout are TTYs. Agent shells are not TTYs, so the scripts silently use defaults and `publish.sh` needs `--yes`; to exercise the prompts use `expect`.
- With Docker running: `./scripts/build.sh --version <v>` (loads the image and runs `dsh --version`), then `docker run --rm <image> --profile web --dump-default-config` to check entry ids, and `docker run --rm <image> web --help` for flags of the installed version.
- `docker compose` needs `.env` to exist (`cp .env.example .env`); never commit `.env` (holds `DEEPSEEK_API_KEY`).
- Upstream is a developer preview with breaking changes: confirm flags, env vars and config ids against the installed version or the upstream docs before changing `docker-entrypoint.sh`, `.env.example` or `cordis.patch.example.yml`.

## Constraints

- Scripts run on macOS default `/bin/bash` 3.2 and in WSL bash 5: no associative arrays, `mapfile`, `${var,,}`, `local -n`; guard possibly empty arrays under `set -u` with `${arr[@]+"${arr[@]}"}`. Shell scripts carry no comments; user-facing text is in `--help`, `README.md` and `.env.example`.
- `.gitattributes` forces LF (the repo is also used from Windows + WSL): shebang scripts must stay LF and executable; the Dockerfile relies on `COPY --chmod=0755`.
- `.dockerignore` is an allowlist (`*`, then `!Dockerfile`, `!docker-entrypoint.sh`): any new file the build needs must be added there.
- `dsh web --host` rejects wildcard addresses, so `docker-entrypoint.sh` detects the container IP; `--no-open` is mandatory (no browser); `DSH_TRUSTED_HOSTS` becomes repeated `--trusted-host` (the Host/Origin fence only admits loopback, the bind IP and these).
- Any entrypoint command other than `web`/`healthcheck` passes straight to `dsh` (`docker run <image> --version`, `headless "task"`).
- Tag scheme is `compute_tags` in `scripts/common.sh`: `<version>` plus one tag per npm dist-tag that points to it; a non-`full` toolset gets a `-<toolset>` suffix. Dist-tags come from `${NPM_REGISTRY%/}/-/package/@deepseek-ai/dsh/dist-tags`.
- Multi-platform pushes need a `docker-container` buildx builder: the script creates `dsh-builder` on demand and selects it with `--builder`, leaving the global default builder alone. `--load` works for a single platform only, which is why `build.sh` and `publish.sh` are separate.
- `NODE_ENV` is deliberately not set in the image (it would make the agent's own `npm install` skip devDependencies).
- README and `.env.example` are written in Russian; script output is English.
