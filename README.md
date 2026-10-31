# mclaude

Runs [Claude Code](https://claude.ai/code) in a throwaway Debian container: one `docker run --rm` per call.
Use `mclaude` instead of `claude`; all arguments and piped input pass through to `claude`.

- **Clean host:** Node.js, npm and Claude Code live only in the image `unimock/mclaude`.
- **Correct ownership:** the container runs as your host UID/GID and user/group names. Files are never root-owned.
- **Per-project scope:** only `$PWD` is mounted, or the matching [area](#areas) with its own SSH keys, git identity and Docker login.

## Quick facts

| | |
|---|---|
| Launcher | `/usr/local/bin/mclaude` (POSIX sh, host side) |
| Image | `unimock/mclaude:<version>` (linux/amd64, linux/arm64), pinned by the launcher |
| Version | = bundled Claude Code release (file `VERSION`) |
| State | `~/.mclaude/` on the host |
| Requires | Docker on the host |
| Not | a sandbox (passwordless sudo inside, mounted dirs writable) |

## Install / update / uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/unimock/mclaude/main/mclaude | sudo install -pm755 /dev/stdin /usr/local/bin/mclaude
sudo rm /usr/local/bin/mclaude        # uninstall
```

Updating = installing a newer launcher. It pulls the image tag it pins on first run.

## Usage

```bash
cd ~/projects/my-project
mclaude                                  # interactive
echo "Summarize the README" | mclaude -p # non-interactive
mclaude --mclaude-docker                 # this run: mount the host Docker socket
mclaude --mclaude-host-network           # this run: docker run --network host
mclaude --mclaude-version                # launcher/image version (--version is claude's)
```

- `--mclaude-*` options may appear anywhere and are not passed to claude. Unknown ones are an error.
- Running from `$HOME` itself is refused.

## Areas

An area is a directory `~/.mclaude/area/<name>/`. When `$PWD` is at or below an area's `path`:
- that whole path is mounted at the same location,
- claude still starts in `$PWD`,
- the area's files below are mounted, and its `args` are added to `docker run`.

If no area matches, the area **`default`** is used: only `$PWD` is mounted, plus `default`'s files and args.

```
~/.mclaude/area/
  default/              # created on first run
    area.conf           # optional; only `args` is used here
    .ssh/
  mygits/
    area.conf
    .ssh/               # optional
    .docker/            # optional
    .gitconfig          # optional
```

**`area.conf`**: one `key = value` per line, `#` comments allowed.

```
path = ~/MyGits
args = -v /var/run/docker.sock:/var/run/docker.sock
args = -p 8080:8080 -e FOO=bar
```

| Key | Meaning |
|---|---|
| `path` | Absolute, `~` allowed. Required except in `default`. `/` and `$HOME` are refused. |
| `args` | Extra `docker run` args, may repeat. Split on whitespace: no quoting, no globbing. `~/` at the start of a word or after `:`/`=` means `$HOME`. |

**Mounted automatically if present** (skipped if the area's `args` already mount the same target):

| In the area dir | Container path | Purpose |
|---|---|---|
| `.ssh/` | `/home/claude/.ssh` | SSH client keys. `id_ed25519` is generated if missing (its public key is printed). |
| `.docker/` | `/home/claude/.docker` | Docker client config, `docker login` credentials |
| `.gitconfig` | `/home/claude/.gitconfig` | git identity |

**Rules**
- Nested areas: the longest matching `path` wins, and only its `args` apply. `/a/b` matches `/a/b/x`, not `/a/bc`.
- Areas share nothing. No `.ssh/` means no SSH key, no `.gitconfig` means no git identity.
- A new area with its own key: `mkdir -m 700 ~/.mclaude/area/<name>/.ssh`. The key is created on the next run.

## Docker inside the container

- The Docker CLI with the buildx and compose plugins is in the image.
- It only works with the host socket mounted:
  - per run: `--mclaude-docker`
  - per area: `args = -v /var/run/docker.sock:/var/run/docker.sock`
- **The socket is root-equivalent on the host.** Grant it only to trusted areas.
- Registry login:
  - Create `~/.mclaude/area/<name>/.docker/`, then run `docker login` inside the container.
  - Credentials are stored base64-encoded, not encrypted, in that area's `.docker/config.json`.
  - The host's `~/.docker` is never used, because its credential helpers don't exist in the container.

## State

| Host | Container | Content |
|---|---|---|
| `~/.mclaude/.claude/` | `/home/claude/.claude/` | Claude config, memory, sessions (all areas) |
| `~/.mclaude/.claude.json` | `/home/claude/.claude.json` | Login/OAuth, onboarding, projects, MCP (all areas). Must be a file; the launcher creates it. |
| `~/.mclaude/area/<name>/` | see [Areas](#areas) | Per-area config, keys, identity, registry login |
| `$PWD` or area `path` | same path | Project files |

## FAQ

- **Where is my login stored?** In `~/.mclaude/.claude.json`, shared by all areas.
- **git has no identity / "Please tell me who you are".** The area has no `.gitconfig`. Fix: `cp ~/.gitconfig ~/.mclaude/area/<name>/`.
- **git push via SSH is denied.** Add the area's `.ssh/id_ed25519.pub` to GitHub & co.
- **How do I install extra packages?**
  - Just for one run: `sudo apt-get update && sudo apt-get install <pkg>`, `npm install -g <pkg>`, or `python3 -m venv ~/.venv`.
  - Permanently: add the package to the Dockerfile and rebuild.
- **Which area is active?** The env var `$MCLAUDE_AREA` inside the container.
- **I still have `~/.mclaude/trusted_areas`.** It is no longer read. Move each line into an `area/<name>/area.conf`.
  - On first run, `~/.mclaude/.ssh` is copied into `area/default/.ssh`.
  - The old global `~/.mclaude/.ssh`, `.docker` and `.gitconfig` are unused and can be deleted afterwards.

## Image contents

- Base: `debian:trixie-slim`
- Claude Code (npm global, owned by the user, so it can self-update)
- Node.js, npm, git, git-lfs, curl, jq, ripgrep, fd-find, rsync, socat, vim
- python3 with pip and venv, g++, shellcheck, ping, openssh-client
- Docker CLI with buildx and compose
- sudo without password

## Repository

| File | Role |
|---|---|
| `mclaude` | Host launcher: options, area matching, mounts, `docker run`. Carries `MCLAUDE_VERSION`, which pins the image tag. |
| `claude-wrapper` | Container entrypoint: sources `setup.sh`, then runs `claude` in `CLAUDE_WORKDIR` as the host user |
| `mclaude-setup` | `/usr/local/lib/mclaude/setup.sh`, sourced as root: maps the `claude` user to `CLAUDE_UID/GID/USER/GROUP`, sudo, docker group, SSH key. Sets `RUN_USER`, starts nothing. |
| `Dockerfile` | Image |
| `docker-bake.hcl` | Tags and build args. Targets `mclaude` (host arch) and `release` (amd64 + arm64). |
| `push.sh` | Builds and pushes `release` as `:latest` + `:$VERSION` |
| `VERSION` | Pinned Claude Code release, e.g. `2.1.314` |

## Build & release

```bash
npm view @anthropic-ai/claude-code version   # latest release → write it into VERSION
export VERSION="$(cat VERSION)" BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
docker buildx bake --load                    # local build, host arch
docker login && ./push.sh                    # multi-arch build + push :latest and :$VERSION
sed -i "s/^MCLAUDE_VERSION=.*/MCLAUDE_VERSION=\"${VERSION}\"/" mclaude   # stamp the launcher
sudo install -pm755 mclaude /usr/local/bin/mclaude
```

- `push.sh` reads `VERSION` itself and warns if the launcher isn't stamped.
- It refuses to push unless bake resolved `:$VERSION`.
- Without `VERSION`, bake builds `:dev` with the latest Claude Code.

## Extending the image

Derived images can reuse the user setup and run their own command, e.g. a long-running variant:

```dockerfile
FROM unimock/mclaude:2.1.314
COPY my-entrypoint /usr/local/bin/
CMD ["/usr/local/bin/my-entrypoint"]
```

```sh
#!/bin/sh -e
. /usr/local/lib/mclaude/setup.sh        # as root; reads CLAUDE_* env, sets RUN_USER
exec su "$RUN_USER" - -c 'exec my-command'
```

## License

MIT, see `LICENSE`.
