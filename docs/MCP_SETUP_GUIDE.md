# MCP Configuration Setup Guide

This guide explains how to configure MCP (Model Context Protocol) servers for both **Claude Code CLI** and **VSCode**.

> **Important:** Claude Code and VSCode use **different configuration files and formats**. You need separate configs for each.

## Prerequisites

1. **Node.js** installed (this guide assumes nvm is used)
2. **MCP server packages** installed globally:

   ```bash
   npm install -g @anthropic-ai/mcp-server-supabase
   npm install -g svelte-mcp
   ```

## File Structure

Create the following files in your project:

```text
your-project/
├── .mcp.json              # Claude Code CLI configuration
├── .vscode/
│   └── mcp.json           # VSCode configuration
└── .envrc                 # Environment variables (keep secret!)
```

## Configuration Differences

| Aspect | Claude Code CLI | VSCode |
| ------ | --------------- | ------ |
| **File location** | `.mcp.json` (project root) | `.vscode/mcp.json` |
| **Root key** | `"mcpServers"` | `"servers"` |
| **Env vars** | `"env": {}` inline object | `"envFile": "path"` |

---

## Claude Code CLI Configuration

### Option A: Using the CLI (Recommended)

```bash
# Add Supabase server
claude mcp add supabase \
  --transport stdio \
  --scope project \
  -e SUPABASE_ACCESS_TOKEN=your-token \
  -e SUPABASE_PROJECT_REF=your-project-ref \
  -- /path/to/mcp-server-supabase

# Add Svelte server
claude mcp add svelte \
  --transport stdio \
  --scope project \
  -- /path/to/svelte-mcp
```

### Option B: Manual Configuration

Create `.mcp.json` in your project root:

```json
{
  "mcpServers": {
    "supabase": {
      "type": "stdio",
      "command": "<path-to-node-bin>/mcp-server-supabase",
      "args": [],
      "env": {
        "SUPABASE_ACCESS_TOKEN": "your-supabase-access-token",
        "SUPABASE_PROJECT_REF": "your-project-reference"
      }
    },
    "svelte": {
      "type": "stdio",
      "command": "<path-to-node-bin>/svelte-mcp",
      "args": [],
      "env": {}
    }
  }
}
```

### Claude Code Configuration Scopes

- **Project scope** (`.mcp.json`): Shareable with team via version control
- **User scope** (`~/.claude.json`): Available across all your projects
- **Local scope** (`~/.claude.json` with project paths): Project-specific but not in repo

---

## VSCode Configuration

Create `.vscode/mcp.json`:

```json
{
  "servers": {
    "supabase": {
      "type": "stdio",
      "command": "<path-to-node-bin>/mcp-server-supabase",
      "envFile": "${workspaceFolder}/.envrc"
    },
    "svelte": {
      "type": "stdio",
      "command": "<path-to-node-bin>/svelte-mcp"
    }
  }
}
```

VSCode uses an `envFile` reference, so create `.envrc`:

```bash
export SUPABASE_ACCESS_TOKEN="your-supabase-access-token"
export SUPABASE_PROJECT_REF="your-project-reference"
```

---

## Finding Your Node Binary Path

If using nvm, find your path with:

```bash
which mcp-server-supabase
# Example output: /home/username/.nvm/versions/node/v24.12.0/bin/mcp-server-supabase
```

Or find your node bin directory:

```bash
dirname $(which node)
# Example output: /home/username/.nvm/versions/node/v24.12.0/bin
```

### Getting Supabase Credentials

1. **SUPABASE_ACCESS_TOKEN**:
   - Go to [Supabase Dashboard](https://supabase.com/dashboard)
   - Navigate to Account → Access Tokens
   - Generate a new token

2. **SUPABASE_PROJECT_REF**:
   - Open your project in Supabase Dashboard
   - The project ref is in the URL: `https://supabase.com/dashboard/project/<project-ref>`
   - Or find it in Project Settings → General

## Step 3: Secure Your Secrets

Add `.envrc` to your `.gitignore` to prevent committing secrets:

```gitignore
# Environment variables with secrets
.envrc
```

## MCP Server Reference

### Supabase MCP Server

Provides tools for:

- Querying and managing Supabase projects
- Executing SQL migrations
- Managing Edge Functions
- Viewing logs and advisors

**Environment Variables:**

| Variable                | Description                                                |
|-------------------------|------------------------------------------------------------|
| `SUPABASE_ACCESS_TOKEN` | Personal access token from Supabase dashboard              |
| `SUPABASE_PROJECT_REF`  | Project reference ID (optional, for single-project setups) |

### Svelte MCP Server

Provides tools for:

- Svelte documentation lookup
- Code autofixing for Svelte 5 syntax
- Playground link generation

**No environment variables required.**

## Troubleshooting

### Server not starting

- Verify the command path exists: `ls -la <path-to-binary>`
- Ensure the package is installed globally: `npm list -g <package-name>`

### Environment variables not loading

- Check that `.envrc` exists and has correct syntax
- Verify the `envFile` path in `mcp.json` uses `${workspaceFolder}`

### Permission denied

- Make the binary executable: `chmod +x <path-to-binary>`

## Quick Setup Script

Create a new project setup with this script:

```bash
#!/bin/bash
# setup-mcp.sh

PROJECT_DIR=${1:-.}
NODE_BIN=$(dirname $(which node))

mkdir -p "$PROJECT_DIR/.vscode"

cat > "$PROJECT_DIR/.vscode/mcp.json" << EOF
{
  "servers": {
    "supabase": {
      "type": "stdio",
      "command": "$NODE_BIN/mcp-server-supabase",
      "envFile": "\${workspaceFolder}/.envrc"
    },
    "svelte": {
      "type": "stdio",
      "command": "$NODE_BIN/svelte-mcp"
    }
  }
}
EOF

cat > "$PROJECT_DIR/.envrc" << EOF
export SUPABASE_ACCESS_TOKEN="your-token-here"
export SUPABASE_PROJECT_REF="your-project-ref-here"
EOF

echo "MCP configuration created in $PROJECT_DIR"
echo "Don't forget to:"
echo "  1. Update .envrc with your actual credentials"
echo "  2. Add .envrc to .gitignore"
```

Usage:

```bash
chmod +x setup-mcp.sh
./setup-mcp.sh /path/to/new/project
```
