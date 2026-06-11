# Zilliz CLI

The official command-line tool for [Zilliz Cloud](https://zilliz.com) — manage clusters, collections, and vector data directly from your terminal.

## Installation

### macOS / Linux

```bash
curl -fsSL https://zilliz.com/cli/install.sh | bash
```

### Windows (PowerShell)

```powershell
irm https://zilliz.com/cli/install.ps1 | iex
```

## Usage

To get started, run `zilliz --help` to see the available commands.

For more information, see the [Zilliz CLI documentation](https://docs.zilliz.com/reference/cli/overview).

## Related Tools

| Tool | Description |
| --- | --- |
| [Zilliz Plugin](https://github.com/zilliztech/zilliz-plugin) | Zilliz Cloud plugin for Claude Code & OpenAI Codex — manage clusters, collections, vector search, backups, and more through natural language. |
| [Gemini-cli Extension](https://github.com/zilliztech/gemini-cli-extension) | Gemini CLI extension for driving Zilliz Cloud via zilliz-cli. |
| [Zilliz Skill](https://github.com/zilliztech/zilliz-skill) | Agent skill that teaches AI agents how to manage Zilliz Cloud vector databases through zilliz-cli. |
| [Milvus Skill](https://github.com/zilliztech/milvus-skill) | Agent skill that teaches LLMs to operate Milvus vector database using pymilvus — connection, collections, vector CRUD, search, hybrid search, full-text search, indexing, RBAC, and common patterns like RAG. |
| [Milvus CLI](https://github.com/zilliztech/milvus_cli) | Milvus Command Line. |
| [Zilliz Launchpad](https://github.com/zilliztech/zilliz-launchpad) | From a sample document to a running Milvus / Zilliz Cloud search app in minutes — an AI-guided scaffold delivered as an Agent skill. |

## Uninstall

### macOS / Linux

```bash
curl -fsSL https://zilliz.com/cli/install.sh | bash -s -- --uninstall
```

If you installed to a custom directory, set the same `ZILLIZ_INSTALL_DIR` when uninstalling:

```bash
ZILLIZ_INSTALL_DIR=/path/to/bin curl -fsSL https://zilliz.com/cli/install.sh | bash -s -- --uninstall
```

### Windows (PowerShell)

```powershell
& ([scriptblock]::Create((irm https://zilliz.com/cli/install.ps1))) --uninstall
```

If you installed to a custom directory, set the same `ZILLIZ_INSTALL_DIR` when uninstalling:

```powershell
$env:ZILLIZ_INSTALL_DIR = "C:\path\to\bin"
& ([scriptblock]::Create((irm https://zilliz.com/cli/install.ps1))) --uninstall
```

The uninstall command removes the `zilliz` binary and the `zz` alias. It also attempts to remove older Python-based installations installed via `pipx`, `uv tool`, or `pip`.

## Alternate commands

### Install

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/zilliztech/zilliz-cli/master/install.sh | bash

# Windows (PowerShell)
irm https://raw.githubusercontent.com/zilliztech/zilliz-cli/master/install.ps1 | iex
```

### Uninstall

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/zilliztech/zilliz-cli/master/install.sh | bash -s -- --uninstall

# Windows (PowerShell)
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/zilliztech/zilliz-cli/master/install.ps1))) --uninstall
```

## License

[Apache-2.0](LICENSE)
