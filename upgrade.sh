#!/bin/bash
# my26-rag-stack upgrade checker
# Checks all stack components for available updates and upgrades on request.
#
# Usage:
#   ./upgrade.sh              # check only, print report
#   ./upgrade.sh --upgrade    # check then prompt per-component
#   ./upgrade.sh --all        # upgrade everything without prompting
#   ./upgrade.sh --python     # upgrade Python packages only
#   ./upgrade.sh --ollama     # upgrade Ollama only (recompiles from source)
#   ./upgrade.sh --qdrant     # upgrade Qdrant binary only
#   ./upgrade.sh --rag        # pull latest rag tool from GitHub

set -e

CHECK_ONLY=true
UPGRADE_ALL=false
TARGET=""

for arg in "$@"; do
  case $arg in
    --upgrade) CHECK_ONLY=false ;;
    --all)     CHECK_ONLY=false; UPGRADE_ALL=true ;;
    --python)  CHECK_ONLY=false; TARGET="python" ;;
    --ollama)  CHECK_ONLY=false; TARGET="ollama" ;;
    --qdrant)  CHECK_ONLY=false; TARGET="qdrant" ;;
    --rag)     CHECK_ONLY=false; TARGET="rag" ;;
  esac
done

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
RAG_REPO="$HOME/src/my26-rag-stack"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✅ $*${NC}"; }
warn() { echo -e "  ${YELLOW}⚠️  $*${NC}"; }
info() { echo -e "  $*"; }

github_latest() {
  curl -sf "https://api.github.com/repos/$1/releases/latest" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','unknown'))" 2>/dev/null \
    || echo "unknown"
}

pypi_latest() {
  curl -sf "https://pypi.org/pypi/$1/json" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['info']['version'])" 2>/dev/null \
    || echo "unknown"
}

prompt_upgrade() {
  local name="$1"
  if $UPGRADE_ALL; then return 0; fi
  read -r -p "  Upgrade $name? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║      my26-rag-stack  upgrade check       ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Ollama ────────────────────────────────────────────────────────────────────
if [[ -z "$TARGET" || "$TARGET" == "ollama" ]]; then
  echo "▶ Ollama"
  current=$(ollama --version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "not found")
  latest=$(github_latest "ollama/ollama")
  info "current: $current  →  latest: $latest"

  if [[ "$current" == "$latest" || "v$current" == "$latest" ]]; then
    ok "Up to date"
  else
    warn "Update available: $current → $latest"
    if ! $CHECK_ONLY && { [[ "$TARGET" == "ollama" ]] || prompt_upgrade "Ollama (recompiles from source, ~20min)"; }; then
      echo "  Fetching $latest..."
      OLLAMA_SRC="$HOME/src/ollama"
      if [[ ! -d "$OLLAMA_SRC" ]]; then
        git clone --depth 1 --branch "$latest" https://github.com/ollama/ollama "$OLLAMA_SRC"
      else
        cd "$OLLAMA_SRC"
        git fetch --tags
        git checkout "$latest"
      fi
      cd "$OLLAMA_SRC"
      echo "  Building llama-server (Metal)..."
      cmake -S llama/server --preset darwin -B build/llama-server-darwin > /tmp/ollama-cmake.log 2>&1
      cmake --build build/llama-server-darwin >> /tmp/ollama-cmake.log 2>&1
      mkdir -p "$HOME/.local/lib/ollama"
      cp build/llama-server-darwin/bin/llama-server "$HOME/.local/lib/ollama/llama-server"
      echo "  Building Ollama binary..."
      go build -ldflags "-X github.com/ollama/ollama/version.Version=$latest" -o ollama .
      launchctl unload "$HOME/Library/LaunchAgents/homebrew.mxcl.ollama.plist" 2>/dev/null || true
      cp ollama "$INSTALL_DIR/ollama"
      launchctl load "$HOME/Library/LaunchAgents/homebrew.mxcl.ollama.plist" 2>/dev/null || true
      sleep 2
      ok "Ollama upgraded to $latest"
    fi
  fi
  echo ""
fi

# ── Qdrant ────────────────────────────────────────────────────────────────────
if [[ -z "$TARGET" || "$TARGET" == "qdrant" ]]; then
  echo "▶ Qdrant"
  if command -v qdrant &>/dev/null || [[ -f "$INSTALL_DIR/qdrant" ]]; then
    current=$(curl -sf http://localhost:6333/ | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','unknown'))" 2>/dev/null || echo "not running")
    latest=$(github_latest "qdrant/qdrant")
    info "current: $current  →  latest: $latest"
    if [[ "$current" == "${latest#v}" ]]; then
      ok "Up to date"
    else
      warn "Update available: $current → $latest"
      if ! $CHECK_ONLY && { [[ "$TARGET" == "qdrant" ]] || prompt_upgrade "Qdrant (binary download)"; }; then
        QDRANT_URL="https://github.com/qdrant/qdrant/releases/download/${latest}/qdrant-aarch64-apple-darwin.tar.gz"
        echo "  Downloading Qdrant $latest..."
        launchctl unload "$HOME/Library/LaunchAgents/com.local.qdrant.plist" 2>/dev/null || true
        curl -sL "$QDRANT_URL" | tar xz -C "$INSTALL_DIR"
        chmod +x "$INSTALL_DIR/qdrant"
        launchctl load "$HOME/Library/LaunchAgents/com.local.qdrant.plist" 2>/dev/null || true
        ok "Qdrant upgraded to $latest"
      fi
    fi
  else
    info "Qdrant not installed locally (using remote)"
  fi
  echo ""
fi

# ── Python packages ───────────────────────────────────────────────────────────
if [[ -z "$TARGET" || "$TARGET" == "python" ]]; then
  echo "▶ Python packages"
  PACKAGES=(qdrant-client ollama sentence-transformers playwright pypdf python-docx beautifulsoup4)
  OUTDATED=()

  for pkg in "${PACKAGES[@]}"; do
    current=$(pip show "$pkg" 2>/dev/null | grep ^Version | awk '{print $2}')
    latest=$(pypi_latest "$pkg")
    if [[ -z "$current" ]]; then
      warn "$pkg: not installed"
    elif [[ "$current" == "$latest" ]]; then
      ok "$pkg $current"
    else
      warn "$pkg: $current → $latest"
      OUTDATED+=("$pkg")
    fi
  done

  if [[ ${#OUTDATED[@]} -gt 0 ]]; then
    if ! $CHECK_ONLY && { [[ "$TARGET" == "python" ]] || prompt_upgrade "Python packages (${OUTDATED[*]})"; }; then
      pip install -q --upgrade "${OUTDATED[@]}"
      ok "Upgraded: ${OUTDATED[*]}"
      echo "  Checking Playwright browser..."
      python3 -m playwright install chromium --quiet
      ok "Playwright browser up to date"
    fi
  fi
  echo ""
fi

# ── rag tool ─────────────────────────────────────────────────────────────────
if [[ -z "$TARGET" || "$TARGET" == "rag" ]]; then
  echo "▶ rag tool (GitHub)"
  if [[ -d "$RAG_REPO" ]]; then
    cd "$RAG_REPO"
    git fetch origin --quiet
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/main)
    if [[ "$LOCAL" == "$REMOTE" ]]; then
      ok "Up to date ($(git log -1 --format='%h %s'))"
    else
      BEHIND=$(git rev-list HEAD..origin/main --count)
      warn "$BEHIND commit(s) behind origin/main"
      git log HEAD..origin/main --oneline | while read -r line; do info "  $line"; done
      if ! $CHECK_ONLY && { [[ "$TARGET" == "rag" ]] || prompt_upgrade "rag tool"; }; then
        git pull --ff-only
        INSTALL_TARGET=$(command -v rag || echo "$INSTALL_DIR/rag")
        cp rag "$INSTALL_TARGET"
        chmod +x "$INSTALL_TARGET"
        ok "rag tool updated"
      fi
    fi
  else
    warn "Repo not found at $RAG_REPO — set RAG_REPO env var or clone first"
  fi
  echo ""
fi

# ── Summary ───────────────────────────────────────────────────────────────────
if $CHECK_ONLY; then
  echo "Run './upgrade.sh --upgrade' to upgrade interactively"
  echo "Or:  './upgrade.sh --all' to upgrade everything"
fi
