# my26-rag-stack

Fully local RAG stack for macOS Apple Silicon. No cloud, no subscriptions, no Homebrew required.

**Stack:** Qdrant · Ollama · qwen3-embedding:8b · BAAI/bge-reranker-v2-m3 · Playwright

---

## Quick Start

```bash
git clone https://github.com/skaboy71/my26-rag-stack
cd my26-rag-stack
chmod +x setup.sh rag
./setup.sh
```

## Setup Options

```bash
# Local Qdrant (default — installs Qdrant binary + launchd service)
./setup.sh

# Remote Qdrant on home server / Unraid
./setup.sh --remote-db 192.168.1.30

# Set Obsidian vault path during setup
./setup.sh --vault "/path/to/your/vault"

# Remote DB + vault
./setup.sh --remote-db 192.168.1.30 --vault "/path/to/vault"

# Skip Ollama install (already installed)
./setup.sh --skip-ollama

# Custom install directory
./setup.sh --install-dir ~/bin
```

---

## Usage

### Health check
```bash
rag status
```

### Ingest

```bash
# Obsidian vault (configured in config.json)
rag add --obsidian
rag add --obsidian personal       # specific vault by name

# Directory of files
rag add --dir ./docs --collection files

# Source code (tree-sitter chunking by symbol boundary)
rag add --codebase ./src --collection code

# Single file (PDF, DOCX, markdown, text, code)
rag add --file ./spec.pdf

# Web crawl — one-time
rag add --url https://docs.spring.io/security/reference/ --depth 2

# Web crawl — persistent (re-crawled on refresh, delta-detected)
rag add --url https://docs.spring.io/security/reference/ --depth 2 --persistent

# Web source from config
rag add --web
rag add --web spring-docs
```

### Query

```bash
rag query "how does JWT authentication work" --json
rag query "rate limiting" --collections code,web --json
rag query "setup instructions" --top-k 15 --json
rag query "auth flow" --no-rerank --json   # skip reranker, raw embedding scores
```

### Collections

```bash
rag collections list              # doc counts per collection
rag collections status            # persistent sources + tracked files/pages
rag collections refresh           # delta-refresh all persistent sources
rag collections rebuild files     # wipe + re-ingest a collection
rag collections rebuild --all
```

---

## Configuration

Config lives at `~/.config/rag/config.json` (created by setup.sh).

```json
{
  "qdrant_url": "http://localhost:6333",
  "ollama_url": "http://localhost:11434",
  "embedding_model": "qwen3-embedding:8b",
  "reranker_model": "BAAI/bge-reranker-v2-m3",
  "collections": ["files", "web", "pdfs", "code"],
  "default_top_k": 8,
  "obsidian_vaults": [
    {"name": "personal", "path": "/path/to/vault", "collection": "files"}
  ],
  "web_sources": [
    {"name": "spring-docs", "url": "https://docs.spring.io/security/reference/", "depth": 2, "collection": "web"},
    {"name": "react-docs",  "url": "https://react.dev/learn", "depth": 3, "collection": "web"}
  ]
}
```

---

## Delta Detection

Refresh only processes what changed — no full re-ingest:

| Source type | Change detection |
|---|---|
| Files / dirs | `mtime` per file — skips unchanged, deletes removed |
| Obsidian vault | `mtime` per note |
| Codebase | `mtime` per source file |
| Web sources | `sha256(full page text)` per URL — skips unchanged pages |

---

## Score Interpretation

| Score | Meaning |
|---|---|
| > 0.85 | High confidence |
| 0.65–0.85 | Reasonable, mild skepticism |
| < 0.5 | Likely noise — broaden query or check ingestion |

---

## Requirements

- macOS Apple Silicon (M1/M2/M3/M4)
- Python 3.10+
- ~10GB disk (models + Qdrant data)
- VPN if using remote Qdrant on home server
