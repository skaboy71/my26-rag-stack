# Contributing to my26-rag-stack

Thanks for helping improve this project! Here's how to get started.

## Getting set up

```bash
# 1. Fork the repo on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/my26-rag-stack
cd my26-rag-stack

# 2. Run setup so you have a working local stack to test against
./setup.sh

# 3. Create a branch for your change
git checkout -b fix/describe-your-fix
```

## Making changes

The main files:

| File | What it does |
|---|---|
| `rag` | The Python CLI tool — all ingestion, search, and crawl logic |
| `setup.sh` | One-shot installer for macOS and Linux |
| `upgrade.sh` | Version checker and updater |

For changes to `rag`, test against a live stack:
```bash
rag status                                    # confirm stack is up
rag add --file ./some-test-file.md            # test ingestion
rag query "something from that file" --json   # test retrieval
rag collections refresh                       # test delta refresh
```

## Submitting a pull request

```bash
git add -A
git commit -m "fix: short description of what you changed"
git push origin fix/describe-your-fix
```

Then open a PR on GitHub against `main`. Include:
- What the bug was / what you changed
- How you tested it (OS, GPU/CPU, any relevant config)

## Reporting bugs

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md) — the more detail the better, especially:
- OS and architecture (`uname -sm`)
- GPU if any (`nvidia-smi` or "Apple Silicon")
- Which command failed and the full error output

## Platform notes

- **macOS Apple Silicon** — primary dev platform, most tested
- **Linux x86_64** — supported, Ollama uses official installer + CUDA auto-detect
- **Linux arm64** — supported (Raspberry Pi 5, Jetson, etc.), CPU only unless ROCm
- **Linux with Nvidia GPU** — install CUDA drivers before running `setup.sh`; Ollama detects automatically

## Things that would be great contributions

- Support for more file types in `rag add --file` (EPUB, HTML, CSV)
- Tree-sitter support for more languages (Go, Rust, Ruby, C++)
- `--watch` mode that actually works (inotify on Linux, FSEvents on macOS)
- Better chunking for PDFs with complex layouts
- A `rag add --jira` or `--confluence` connector
- Tests
