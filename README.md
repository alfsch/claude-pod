# claude-pod

> Docker sandbox for the Claude Code CLI. Runs Claude against one project folder — including with `--dangerously-skip-permissions` — while your home directory, SSH keys, and other projects stay invisible to the container. Unofficial.

![claude-pod](assets/cover.jpeg)

## TL;DR

`claude-pod` runs Claude Code inside a Docker container that mounts the project folder you launch it from. Claude can read and edit that folder; the rest of your machine — home directory, SSH keys, other projects, host shell — isn't mounted, so the container can't see it.

It's useful in two cases:

- With `--dangerously-skip-permissions`: you get auto-approval without giving Claude access to your whole machine.
- In normal, prompt-by-prompt mode: the container still caps the blast radius, so an over-broad command, prompt injection, or a malicious dependency can't reach past the project folder.

It's not full isolation — here's the boundary:

- ✅ **Outside the launch folder is unreachable.** Your home directory, `~/.ssh`, `~/.aws`, other projects, and the host shell aren't mounted, so the container can't see them.
- ⚠️ **Inside the launch folder is fully exposed.** Any `.env`, `.git/config`, or keys in it are readable and writable; outbound network is open, so contents can be read or exfiltrated; and your Anthropic login is stored on the host under `~/.claude-pod/`.
- 🚫 **Don't launch from `~` or `/` or other sensitive folders.** That mounts your whole home or filesystem into the container and defeats the point.

The practical effect: the worst case is narrowed from "your whole machine" to "this one folder," which is recoverable from git.

```sh
# Clone this repo once, anywhere you like (~/tools/claude-pod is just an example)
git clone https://github.com/trekhleb/claude-pod.git ~/tools/claude-pod

# Build the image (once) — runs from anywhere, no cd needed
~/tools/claude-pod/install.sh

# cd into your project, then launch Claude
cd ~/projects/your-project
~/tools/claude-pod/claude-pod claude --dangerously-skip-permissions

# Long path? You can alias it — see "Aliases" below.

# Need Docker inside the pod? Prefix with DOCKER=1 — see "Using Docker inside the pod" below.
# DOCKER=1 ~/tools/claude-pod/claude-pod

# Forgot a command later? Print a copy-pastable cheatsheet of all of them
~/tools/claude-pod/claude-pod --help
```

Docker is the only requirement — no Node.js, npm, or `claude` needed on your host. For the full threat model and the four-file design, see [Security and limits](#security-and-limits). For the official approach, see Anthropic's [Claude Code sandboxing documentation](https://code.claude.com/docs/en/sandboxing).

## Contents

- [Usage](#usage)
  - [Requirements](#requirements)
  - [Running claude-pod](#running-claude-pod)
  - [Aliases](#aliases)
  - [First launch (login)](#first-launch-login)
  - [Exposing ports](#exposing-ports)
  - [Using Docker inside the pod](#using-docker-inside-the-pod)
    - [Keeping images between sessions](#keeping-images-between-sessions)
  - [Pasting images and screenshots](#pasting-images-and-screenshots)
  - [Updating or pinning the Claude Code version](#updating-or-pinning-the-claude-code-version)
  - [Customizing the image](#customizing-the-image)
- [Security and limits](#security-and-limits)
  - [What it actually does](#what-it-actually-does)
  - [What is and isn't isolated](#what-is-and-isnt-isolated)
  - [Network isolation and resource limits](#network-isolation-and-resource-limits)
  - [Side effects outside the project folder](#side-effects-outside-the-project-folder)
- [Reference](#reference)
  - [Platforms](#platforms)
  - [Uninstall](#uninstall)
  - [License and trademarks](#license-and-trademarks)

## Usage

### Requirements

**Just Docker.** Claude Code runs inside the container, not on your host — you do not need Node.js, npm, or the `claude` CLI installed on your machine. The host stays untouched apart from one state folder (`~/.claude-pod/`) that exists only to keep your login across container restarts.

### Running claude-pod

Call the script using its full or relative path from any project:

```sh
cd ~/projects/anything
~/tools/claude-pod/claude-pod
```

You land in a bash shell at the same path your project lives at on the host (e.g. `/Users/you/projects/anything`), with `claude` on `PATH`. Run it however you like:

```sh
claude --dangerously-skip-permissions
```

Alternatively, you may skip the shell and go straight into Claude. Anything you pass to `claude-pod` is run inside the container instead of bash. So this drops you directly into Claude in one command, and exits the container when Claude exits:

```sh
~/tools/claude-pod/claude-pod claude --dangerously-skip-permissions
```

To exit, type `exit`.

Forgot a command later? Run `~/tools/claude-pod/claude-pod --help` (or `-h`) anytime — it prints a copy-pastable cheatsheet of every command (run, install, update, uninstall, options), with the correct absolute paths for your install.

### Aliases

For your convenience, you can add an alias to your shell configuration file (`~/.zshrc`, `~/.bashrc`, etc.):

```sh
alias claude-pod=~/tools/claude-pod/claude-pod
```

This is the shell-first form: `claude-pod` drops you into the container with `claude` on `PATH`, so you can run `npm install`, a dev server, or tests and then start `claude` yourself — all inside the sandbox. The same alias also goes straight into Claude when you pass the command through: `claude-pod claude --dangerously-skip-permissions`.

### First launch (login)

The first time you start Claude inside the pod, it will print a login URL. Open it in your host browser, complete the login, paste the verification code back into the container, and you're done. The session persists in `~/.claude-pod/` and survives container restarts — you only do this once per machine.

### Exposing ports

By default, `claude-pod` doesn't publish any ports to the host (outbound traffic is still unrestricted — see [What is and isn't isolated](#what-is-and-isnt-isolated)). Map ports through with the `PORTS` environment variable:

```sh
# Map a single port (127.0.0.1:3000 -> container:3000)
PORTS=3000 claude-pod

# Map multiple ports
PORTS="3000 5173" claude-pod

# Map a specific host port to a different container port
PORTS="8080:80" claude-pod

# Or, alternatively, without using aliases
PORTS="5173:5173" ~/tools/claude-pod/claude-pod
```

> **Bind your dev server to `0.0.0.0` inside the container, not `localhost`.** Most dev servers default to `localhost`, which means they only listen on the container's own loopback — your host browser can't reach them even with `PORTS=...` set. Common fixes:
> - **Vite:** `npm run dev -- --host` (or `vite --host 0.0.0.0`)
> - **Next.js:** `next dev -H 0.0.0.0`
> - **Create React App / webpack-dev-server:** `HOST=0.0.0.0 npm start`
> - **Django:** `manage.py runserver 0.0.0.0:8000`
> - **Rails:** `rails s -b 0.0.0.0`
>
> The host-side mapping is still `127.0.0.1`-only (forced by `claude-pod`), so binding `0.0.0.0` inside the container does not expose your dev server to your LAN.

### Using Docker inside the pod

Set `DOCKER=1` to get a throwaway Docker daemon for the session (build images, run containers, `docker compose`).

**Quick start**

1. Make sure the image is current. The `docker` CLI was added to the image, so re-run the installer once if you built it earlier:

   ```sh
   ~/tools/claude-pod/install.sh
   ```

2. `cd` into your project and launch with `DOCKER=1`, either into a shell or straight into Claude:

   ```sh
   cd ~/projects/your-project
   DOCKER=1 ~/tools/claude-pod/claude-pod                 # shell
   DOCKER=1 ~/tools/claude-pod/claude-pod claude --dangerously-skip-permissions  # straight into Claude
   ```

   You'll see `● Starting Docker sidecar...` for a few seconds on the first start while the sidecar image is pulled.

3. Use Docker as usual inside the pod:

   ```sh
   docker version          # client and server should both answer
   docker run --rm hello-world
   docker compose up -d
   ```

Combine it with the other options if you like, e.g. `DOCKER=1 MEMORY=8g CPUS=4 PORTS=3000 claude-pod`. With an alias (see [Aliases](#aliases)) it is just `DOCKER=1 claude-pod`.

If it doesn't start, check that your own Docker can run privileged containers (the sidecar needs `--privileged`) and that you aren't also setting `NET=none`. A sidecar that never becomes ready prints its last log lines.

How it works: `claude-pod` starts a separate **rootless Docker-in-Docker sidecar** (the pinned `docker:<major>-dind-rootless` image) on a private per-run network and points the pod's `docker` CLI at it. Only the sidecar runs `--privileged`; the pod keeps all its hardening (no capabilities, `no-new-privileges`, default seccomp). The host's Docker socket is never mounted. The daemon is only reachable with a per-run client certificate (mutual TLS), shared with the pod through a throwaway volume. The sidecar, network and volume are removed when the session ends, taking its images and containers with it. It works on Linux, macOS and Windows (WSL2).

**Requirements for `DOCKER=1`**

- A Docker host where privileged containers are allowed (Docker Desktop on macOS/Windows works out of the box).
- On Linux the rootless daemon in the sidecar needs unprivileged user namespaces. Ubuntu 24.04 and newer restrict them through AppArmor, and the sidecar then fails with `rootlesskit ... fork/exec /proc/self/exe: operation not permitted` (the launcher points here). Check with `sysctl kernel.apparmor_restrict_unprivileged_userns`; if it is `1`, allow them permanently:

  ```sh
  echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | sudo tee /etc/sysctl.d/99-claude-pod-userns.conf
  sudo sysctl --system
  ```

  or only until the next reboot: `sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0`. This loosens the restriction for every program on the machine, not just claude-pod. To undo it, delete the file and set the value back explicitly, because `sysctl --system` only applies configured values and does not restore the kernel default (a reboot works too):

  ```sh
  sudo rm /etc/sysctl.d/99-claude-pod-userns.conf
  sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=1
  ```
- The rootless daemon runs without cgroups, so `docker run --memory/--cpus` inside the pod has no effect. `MEMORY`, `CPUS` and `PIDS` still limit the sidecar as a whole.

Things to know:

- The sidecar is privileged (inside Docker's VM on macOS/Windows). A kernel or runtime escape from it would be more serious than from the default pod, so use `DOCKER=1` only on projects you trust.
- The project folder is mounted into the sidecar at the same path, so `docker run -v "$PWD:/app" ...` works. On Linux with a host uid other than 1000, the launcher builds a small sidecar image once (a few seconds, `claude-pod-dind:*`) whose user has your uid, so inner containers that run as root (the default for most images) can write to the project as you. Inner containers that run as a non-root user (an image with `USER`, `--user`, compose `user:`) cannot, unless the folder is group-writable (`chmod g+w`) and they run with group 0; the files they create are owned by a high uid on the host. On macOS and WSL2 this is not tested; with a `DIND_IMAGE` of your own it is skipped.
- Both Docker images (the CLI in the pod, the sidecar) are pinned by digest; `DIND_IMAGE` overrides the sidecar.
- Ports published by inner containers (`docker run -p ...`) live on the sidecar's network, not on your host. `PORTS=...` only publishes ports of the pod itself, so it does not make an inner service reachable from the host. From inside the pod, reach it at `dind:<published-port>` (e.g. `curl http://dind:8080`); to open it from the host browser, run a small proxy in the pod that listens on a `PORTS` port and forwards to `dind:<port>`, or run the dev server in the pod instead. This is not a security boundary: on native Linux the sidecar's bridge network is routable from the host, so a port an inner container publishes on all interfaces can still be reached from the host via the sidecar's bridge IP. Bind such ports to `127.0.0.1` inside the sidecar (`-p 127.0.0.1:8080:80`) if that matters.
- To cancel a `DOCKER=1` launcher that a script started in the background (`claude-pod ... &`), send it SIGTERM (`kill $!`), not SIGINT: non-interactive shells start background jobs with SIGINT ignored, and Bash can't override that. Ctrl-C in a terminal and SIGINT from an interactive shell work. Either signal stops the pod first and then removes the sidecar, network and certificate volume.
- `DOCKER=1` and `NET=none` are mutually exclusive. `MEMORY`, `CPUS` and `PIDS` apply to the sidecar too. Set `DIND_IMAGE=...` to use a different sidecar image (pin it by digest).
- Changing this feature? See [docs/docker-sidecar.md](docs/docker-sidecar.md) for the design, the lifecycle invariants and how to test it.
- Images are re-pulled every session by default. See [Keeping images between sessions](#keeping-images-between-sessions) to reuse them.

#### Keeping images between sessions

Add `DOCKER_CACHE=1` to keep the sidecar's images, layers and volumes between sessions, so nothing is re-pulled or rebuilt:

```sh
DOCKER=1 DOCKER_CACHE=1 claude-pod
```

- The data lives in a Docker named volume `claude-pod-docker-<SHA-256 of the project path and the sidecar's uid and gid, first 16 hex characters>`, one per project. It is not a host folder: overlay storage doesn't work on macOS/Windows file shares, and the directory has to be owned by the sidecar's uid.
- On startup you'll see either `Docker cache: created new ...` or `Docker cache: reusing ... (N images, SIZE)`, so you can tell at a glance whether the cache is working.
- Only one session per project can use the cache at a time; a second one stops with a message. Run it without `DOCKER_CACHE=1` for a throwaway daemon alongside.
- **Security trade-off:** whatever a session pulled or built, including anything malicious or secret, is still there in the next one. Skip it for untrusted code.
- Caches that haven't been used for 90 days are removed automatically the next time any project starts with `DOCKER_CACHE=1`. Change the limit with `DOCKER_CACHE_MAX_AGE_DAYS=30`, or disable it with `DOCKER_CACHE_MAX_AGE_DAYS=0`. Docker doesn't track volume usage itself, so each cache gets an empty marker file whose modification time is its last use, in `~/.local/state/claude-pod/caches/` (or under `$XDG_STATE_HOME`). That is deliberately outside `~/.claude-pod/`, so the pod can't see or alter it.
- Otherwise the cache grows until you clean it. Inspect with `docker volume ls --filter name=claude-pod-docker-`, delete one with `docker volume rm <name>`; `uninstall.sh` removes them all.

### Pasting images and screenshots

Claude can only read files that live **inside the project folder** — that's the one directory bind-mounted into the container. Images on your Desktop or in Downloads aren't mounted, so pasting one straight from there hands Claude a path it can't reach. This is the same isolation that keeps the rest of your machine private from the container ([What is and isn't isolated](#what-is-and-isnt-isolated)); the small bit of friction below is the price for not exposing those default locations.

The workaround:

1. Take the screenshot as usual (it lands on the Desktop, or wherever your OS drops it).
2. Copy the file into your project folder — anywhere under it works, e.g. a `tmp/` subfolder.
3. **Re-copy the file from that new in-project location**, so the path on your clipboard points at the copy that's actually synced into the container.
4. Paste into Claude. The path now resolves inside the container and the image is recognized.

### Updating or pinning the Claude Code version

By default, `install.sh` installs the current official release (npm's `stable` dist-tag). It resolves `stable` to a concrete version first, so Docker's cache is reused until a new stable release appears. It resolves its own location, so you can re-run it from any folder:

```sh
~/tools/claude-pod/install.sh
```

To pin a specific version, set `CLAUDE_CODE_VERSION`:

```sh
CLAUDE_CODE_VERSION=2.0.0 ~/tools/claude-pod/install.sh
```

To track the newest build instead of the official release, pin to `latest` (always refetched, bypassing Docker's cache):

```sh
CLAUDE_CODE_VERSION=latest ~/tools/claude-pod/install.sh
```

**Automatic updates on start.** If the image was built from the default `stable` channel, every `claude-pod` start checks npm for a newer stable release (3-second timeout) and, if there is one, rebuilds the image via `install.sh` before launching. Offline or failed check/rebuild? It prints a note and continues with the existing image. Images pinned to a version or to `latest` are never auto-updated, and neither is an image built before this feature existed — re-run `install.sh` once to opt in. Skip the check for a single run with `CLAUDE_POD_NO_UPDATE=1 claude-pod`.

Pinned versions cache normally across rebuilds. The script prints the resolved version after each build, so you always know what you got.

### Customizing the image

The image is intentionally minimal: `node:24-slim` + `git` + `curl` + `less` + `jq` + `gh` + `yq` + `python3` + `pip` + `venv` + `pdftotext` (poppler-utils) + `qpdf` + `tesseract` (English, German) + Claude Code. Nothing project-specific. Anything else your projects need (build tools, other toolchains, more OCR languages) you add yourself — edit the `Dockerfile` and re-run `~/tools/claude-pod/install.sh`.

## Security and limits

### What it actually does

The whole tool is four tiny files:

- **`Dockerfile`** — `node:24-slim` + `git` + `curl` + `less` + `jq` + `gh` + `yq` + `python3` + `python3-pip` + `python3-venv` + `poppler-utils` + `qpdf` + `tesseract-ocr` (eng, deu) + `@anthropic-ai/claude-code`.
- **`claude-pod`** — one `docker run` command that mounts your current directory (plus a small state dir for login and history) and nothing else of your machine.
- **`install.sh`** — checks Docker and builds the image. Doesn't touch any system path; the tool stays self-contained in this folder.
- **`uninstall.sh`** — removes the image and `~/.claude-pod/` (auth + session history) after confirmation. Lists what it doesn't touch so you can clean those up yourself.

### What is and isn't isolated

**Safe from Claude:**
- Everything outside the project folder you launched from. `~/.ssh`, `~/.aws`, `~/.zshrc`, browser data, other projects — all unreachable.
- The host shell. No way to execute commands on your host machine.

**Still exposed:**
- **The project folder itself.** Anything inside it — `.env`, `.git/config` (which can carry credentials for private remotes), private keys committed by mistake, `node_modules`, sibling worktrees, scratch files — is fully readable *and* writable by code running in the container. Don't run `claude-pod` from a folder whose contents you wouldn't trust the AI (or a malicious dependency it just installed) to see and modify.
- **The network.** Outbound is unrestricted by default. A malicious payload could exfiltrate the project contents or burn your Anthropic API quota. For offline work you can cut networking entirely with `NET=none` (see [Network isolation and resource limits](#network-isolation-and-resource-limits)), but that also takes Claude itself offline — there's no built-in egress allowlist that would keep Claude online while blocking everything else.
- **Your Anthropic login** (stored in `~/.claude-pod/` on the host, separate from any host Claude install, shared across sandboxed projects).

**Where Claude can actually write** — two paths, both intentional bind mounts:
- The project folder, bind-mounted at the same path inside the container (`$PWD:$PWD`). Edits land on your host's disk directly, no copy.
- `~/.claude-pod/` on the host, mounted at `/home/claude-pod/.claude`. Holds the auth token and session history.

> Because the current directory (`$PWD`) is mounted into the container, **avoid running this tool from directories like root (`/`) or `/etc` or other sensitive ones**. In such cases you are giving the AI access to your entire machine or to other sensitive data, defeating the purpose of the sandbox. Always `cd` into your specific project folder first.

Everywhere else Claude writes is either in the container's ephemeral filesystem (discarded on exit thanks to `--rm`) or simply has no path to land at — the Linux kernel's mount namespace makes any other host directory invisible to the container. Symlinks inside the project folder pointing to `~/.ssh` or `/etc/passwd` appear broken for the same reason: those targets aren't mounted, so the container can't see them.

> **Hardlinks are different.** A hardlink is a second name for an existing inode on the same filesystem. If a file inside your project folder is hardlinked to a sensitive file elsewhere on the same filesystem (e.g., `~/.ssh/id_rsa`), the container *can* reach it through the hardlink — the bind-mount exposes the inode, not just the path. This requires the hardlink to already exist in the project folder, so it's a real concern only when you're inspecting code from an untrusted source. Treat unfamiliar projects with the same caution you'd apply to running their code directly: don't run `claude-pod` inside a folder you don't trust.

The tradeoff: the worst case becomes "something bad happens to one project folder," which is recoverable from git, instead of "my entire home directory is exposed."

### Network isolation and resource limits

By default the container has **unrestricted outbound network** (Claude needs `api.anthropic.com`, your builds need npm/pip/etc.) and a generous process cap. When you're about to let Claude loose on code from an untrusted source, you can tighten things further with environment variables — all of them just add flags to the same `docker run`, nothing else changes:

```sh
# Cut ALL networking for the run. A malicious payload can't exfiltrate the project or phone home.
# Note: Claude itself can't reach Anthropic with no network, so this is for offline shell/build
# work (inspecting or building untrusted code), not for a live Claude session.
NET=none claude-pod

# Cap memory and CPU so a runaway or malicious build can't exhaust the host (recoverable via OOM,
# but disruptive). No default cap — a fixed limit would kill legitimate large builds.
MEMORY=4g CPUS=2 claude-pod

# Lower the process/thread cap when running untrusted code (default is 4096, generous for builds).
PIDS=512 claude-pod
```

`NET=none` and `PORTS` are mutually exclusive — a container with no network can't publish ports. `--pids-limit` is always applied (it contains fork bombs, which dropped capabilities do *not* prevent); raise `PIDS=` if a very parallel build hits the ceiling.

### Side effects outside the project folder

Everything this repo causes to exist outside the project you launch it from:

- `~/.claude-pod/` on your host — auth token, settings, and per-project session/conversation history (transcripts can include code snippets and command output Claude saw). Auth and settings are shared across projects (one login, ever); session history lives under `~/.claude-pod/projects/<encoded-host-path>/`, one folder per project, using the same encoding host-Claude uses — so if you ever switch to a host install, you can copy the folders over and keep your transcripts. This is *not* a host Claude install; it's a state directory for the container's Claude, kept on the host so it survives restarts.
- Docker image `claude-pod` and its layers, plus the `node:24-slim` base image, in Docker's image store. With `DOCKER_CACHE=1`, also one `claude-pod-docker-*` volume per project; with `DOCKER=1` on a Linux host whose uid is not 1000, also a `claude-pod-dind:*` image. The last-use markers for pruning them are kept in `~/.local/state/claude-pod/caches/` (the only host path outside `~/.claude-pod/`, created only with `DOCKER_CACHE=1`).
- Docker build cache from `apt-get` and `npm install` steps.
- Outbound network during build: Docker Hub, Debian apt mirrors, npm registry. During runtime: `api.anthropic.com` and whatever your project code reaches (network is unrestricted).
- While a session is running: one container process, and any ports you explicitly mapped via `PORTS` bound on `127.0.0.1`.

No `sudo`, no writes to `/usr/local/`, `/etc/`, `~/.zshrc`, `~/Library/`, your existing `~/.claude/`, or anywhere else on the host.

## Reference

### Platforms

The wrapper is portable POSIX bash + Docker. It should work on any host with a recent Docker:

- **macOS** (Apple Silicon and Intel) with Docker Desktop, OrbStack, or Colima — primary development target.
- **Linux** with Docker Engine or Docker Desktop — bind mounts and `--user` UID/GID map directly here, the most native experience.
- **Windows + WSL2** with Docker Desktop's WSL2 backend — run `claude-pod` from inside a WSL distribution's bash shell.

**Native Windows** (`cmd.exe` / PowerShell) is not supported. The wrapper is a bash script and uses POSIX tools (`id`, etc.); use WSL2 instead.

If a platform doesn't behave as expected, please open an issue.

### Uninstall

```sh
~/tools/claude-pod/uninstall.sh
```

Removes `~/.claude-pod/`, the `claude-pod` image, any `DOCKER_CACHE` volumes and any `claude-pod-dind` sidecar images after confirmation. Tells you exactly what it isn't touching (`node:24-slim`, build cache, this repo) and how to clean those up yourself.

If you added a shell alias for convenience (e.g. `alias claude-pod=...` in `~/.zshrc` / `~/.bashrc`), remove that line too — `uninstall.sh` doesn't touch your shell rc files.

### License and trademarks

The code in this repository is released under the MIT License — see [`LICENSE`](LICENSE) for the full text.

Claude Code itself is a separate product owned by Anthropic, PBC, and is **not** redistributed by this project — `install.sh` fetches it from npm at build time. This project is not affiliated with, endorsed by, or sponsored by Anthropic, PBC. "Claude" and "Claude Code" are trademarks of Anthropic, PBC, referenced here nominatively. No Anthropic logos, wordmarks, or other brand assets are used.
