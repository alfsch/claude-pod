# If you bump this tag, also update the literal in uninstall.sh.
FROM node:24-slim

# git/curl/less are baseline dev tools; jq and gh are reached for by Claude's built-in workflows
# (JSON pipelines and the GitHub CLI for PRs/issues/releases). ca-certificates is needed for HTTPS.
# python3 and pip are for scripting; poppler-utils provides pdftotext, qpdf handles PDF
# manipulation, and tesseract-ocr does OCR (English and German language data).
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates curl less jq gh \
      python3 python3-pip poppler-utils qpdf tesseract-ocr tesseract-ocr-eng tesseract-ocr-deu \
 && rm -rf /var/lib/apt/lists/*

# yq (mikefarah's Go implementation, not Debian's Python wrapper of the same name) isn't in apt, so
# fetch the pinned release binary. Each architecture's SHA-256 comes from the release's `checksums`
# file; the build fails if the download doesn't match. TARGETARCH is set by BuildKit (amd64/arm64).
# When bumping YQ_VERSION, update both hashes.
ARG TARGETARCH
ARG YQ_VERSION=v4.54.1
RUN case "$TARGETARCH" in \
      amd64) YQ_SHA256=8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f ;; \
      arm64) YQ_SHA256=189088da0c6429ec5178dfaab1a114805f6cab0b61b165ab236efedf1d57a71b ;; \
      *) echo "yq: unsupported architecture '$TARGETARCH'" >&2; exit 1 ;; \
    esac \
 && curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${TARGETARCH}" \
 && echo "${YQ_SHA256}  /usr/local/bin/yq" | sha256sum -c - \
 && chmod +x /usr/local/bin/yq

# Override at build time with --build-arg CLAUDE_CODE_VERSION=2.x.y to pin a specific
# version, or "latest" for the newest build. Default "stable" is npm's official release channel.
ARG CLAUDE_CODE_VERSION=stable

# install.sh resolves "stable" to a concrete version, so the version literal itself is the cache
# key and this layer caches normally. For "latest" (a tag whose literal never changes), install.sh
# passes CACHEBUST=$(date +%s) to force a fresh refetch.
ARG CACHEBUST=1
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Recorded for the claude-pod launcher: it only auto-updates images built from the "stable" channel
# (CLAUDE_CODE_CHANNEL, what the user asked for) and compares the installed version label against
# npm's current stable. Declared after the install so changing them doesn't invalidate that layer.
ARG CLAUDE_CODE_CHANNEL=${CLAUDE_CODE_VERSION}
LABEL claude-pod.channel=${CLAUDE_CODE_CHANNEL} \
      claude-pod.version=${CLAUDE_CODE_VERSION}

# We DO NOT use `USER node` here. Instead, we pass `--user "$(id -u):$(id -g)"` dynamically
# at runtime in the `claude-pod` script. This ensures perfect file permission alignment
# between the host and the container, especially on Linux environments.
# Create a dedicated, globally writable home directory for our dynamic runtime user.
RUN mkdir -p /home/claude-pod && chmod 777 /home/claude-pod

# Interactive-shell setup, appended to /etc/bash.bashrc. Only interactive bash sources this file, so
# none of it touches the non-interactive `claude-pod claude ...` path. The dynamic, /etc/passwd-less
# user has no $HOME/.bashrc of its own, so these baseline conveniences have to live in the system-wide
# rc. Heredoc keeps the escapes readable (BuildKit, which install.sh already requires via
# --progress=plain, supports it).
RUN cat >> /etc/bash.bashrc <<'EOF'

# Colored prompt: green label, blue path — the conventional Debian default look. \[...\] wraps the
# non-printing escapes so bash measures the prompt width correctly. The "claude-pod" label also
# hides the "I have no name!" warning a dynamic, passwd-less user would otherwise show.
PS1='\[\e[1;32m\]claude-pod\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '

# Basic, conventional coloring for the most-used commands. dircolors supplies the standard LS_COLORS
# palette; the aliases enable color only when output is a terminal (so piped output stays clean).
if command -v dircolors >/dev/null 2>&1; then eval "$(dircolors -b)"; fi
alias ls='ls --color=auto'
alias grep='grep --color=auto'
EOF

CMD ["bash"]
