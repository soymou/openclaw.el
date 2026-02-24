# openclaw.el

Emacs integration for the [OpenClaw](https://openclaw.ai) AI assistant.

## How it works

The package spawns `openclaw acp` as a subprocess and communicates with it via
**JSON-RPC 2.0 over NDJSON** (newline-delimited JSON on stdin/stdout).  The ACP
bridge connects to your OpenClaw Gateway over WebSocket, so the gateway can be
on a remote machine — only the Emacs host needs `openclaw` installed.

```
Emacs  ←─ NDJSON/stdio ─→  openclaw acp  ←─ WebSocket ─→  Gateway (remote)
```

## Requirements

- Emacs 28.1+
- `openclaw` CLI installed on this machine (`/opt/homebrew/bin/openclaw` on macOS)
- OpenClaw Gateway running somewhere (local or remote)

## Installation

### Manual

```elisp
(add-to-list 'load-path "~/Desktop/openclaw.el")
(require 'openclaw)
```

### use-package

```elisp
(use-package openclaw
  :load-path "~/Desktop/openclaw.el"
  :config
  (setq openclaw-executable    "/opt/homebrew/bin/openclaw"
        openclaw-gateway-url   "ws://192.168.1.100:18789"   ; your server IP
        openclaw-gateway-token "your-secret-token")
  (openclaw-setup-keys))   ; binds C-c o prefix
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `openclaw-executable` | `/opt/homebrew/bin/openclaw` | Path to openclaw CLI |
| `openclaw-gateway-url` | `nil` (local) | Gateway WebSocket URL |
| `openclaw-gateway-token` | `nil` | Gateway auth token |
| `openclaw-default-agent` | `"main"` | Default agent ID |
| `openclaw-window-width` | `0.35` | Sidebar width (0–1) |

### Remote gateway setup

The gateway runs on your server and binds to loopback by default (`127.0.0.1`).
To reach it from another machine you have two options:

**Option A — SSH tunnel (no gateway reconfiguration needed):**
```bash
# On your Mac, keep this running in the background:
ssh -N -L 18789:127.0.0.1:18789 mou-server
# Then in Emacs:
# (setq openclaw-gateway-url "ws://127.0.0.1:18789")
```

**Option B — Bind gateway to LAN interface (on the server):**
```bash
openclaw config set gateway.bind lan
openclaw gateway restart
# Then in Emacs:
# (setq openclaw-gateway-url "ws://192.168.1.XXX:18789")
```

Get your gateway token:
```bash
# On the server:
openclaw config get gateway.auth.token
```

## Keybindings

### Global (after `openclaw-setup-keys`)

| Key | Command | Description |
|---|---|---|
| `C-c o o` | `openclaw-chat-toggle` | Open/close chat sidebar |
| `C-c o c` | `openclaw-context-add-buffer` | Add current file to context |
| `C-c o r` | `openclaw-context-add-region` | Add selected region to context |
| `C-c o p` | `openclaw-context-add-project` | Add project root to context |
| `C-c o s` | `openclaw-sessions-switch` | Switch session |
| `C-c o n` | `openclaw-sessions-new` | New session |
| `C-c o k` | `openclaw-process-stop` | Kill subprocess |

### In chat buffer

| Key | Command | Description |
|---|---|---|
| `RET` | `openclaw-chat-send` | Send message |
| `C-c C-c` | `openclaw-chat-abort` | Abort current run |
| `C-c C-k` | `openclaw-chat-clear` | Clear display |
| `C-c C-s` | `openclaw-sessions-switch` | Switch session |
| `C-c C-n` | `openclaw-sessions-new` | New session |
| `TAB` | complete slash command | Tab-complete `/cmd` |
| `M-p` / `M-n` | input history | Previous / next input |

## Slash commands

| Command | Description |
|---|---|
| `/help` | List all slash commands |
| `/status` | Session count and active session ID |
| `/model <name>` | Switch model (e.g. `/model opus`, `/model sonnet`) |
| `/thinking <level>` | Set thinking level: `off` `minimal` `low` `medium` `high` |
| `/session [key]` | List sessions or switch to `key` |
| `/new` | Create a new session |
| `/clear` | Clear the chat display |
| `/stop` | Abort current agent run |
| `/context` | Show pending context items |
| `/reconnect` | Restart the `openclaw acp` subprocess |

## Context injection

Before sending a message, add context with:

- **`C-c o c`** — entire current buffer (file content)
- **`C-c o r`** — selected region
- **`C-c o p`** — project root path

Context is prepended to your next message as fenced code blocks and cleared
after sending.  You can stack multiple items.  Check what is pending with `/context`.

## Tool calls & permissions

When the agent calls a tool that requires confirmation, a `completing-read`
prompt appears in the minibuffer listing the available options (Allow / Deny).
Your choice is sent back to the agent automatically.

Tool calls are shown inline in the chat:
```
[Tool: Read file.el (pending)]
[Tool call123: completed]
```

## File structure

```
openclaw.el          — Main entry point, config, key prefix
openclaw-process.el  — Subprocess management, NDJSON parsing
openclaw-protocol.el — JSON-RPC 2.0 dispatch, ACP handshake
openclaw-chat.el     — Chat sidebar UI, streaming output
openclaw-sessions.el — Session list/switch/create
openclaw-context.el  — File/region/project context injection
openclaw-commands.el — Slash command registry and built-ins
openclaw-ui.el       — Faces, markdown rendering, formatting
```
