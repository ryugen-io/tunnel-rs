# rustunnl

Universal SSH Reverse Tunnel Manager (will be Rust-refactored later)

## Overview

`rustunnl` manages persistent SSH reverse tunnels with automatic reconnection. Perfect for accessing services behind NAT/firewall from external servers.

## Features

- Multiple tunnel configurations
- XDG-compliant directory structure
- Auto-reconnect via autossh
- Fish shell integration
- Git-trackable (no secrets in repo)

## Directory Structure

```
Project:
/data/code/devel/local.projects/rustunnl/
├── rustunnl.sh                 # Main script
├── examples/
│   └── tunnel-config.example   # Example configuration
└── README.md

User Config (XDG):
~/.config/rustunnl/
└── <name>.env               # Tunnel configurations

User State:
~/.local/state/rustunnl/
├── <name>.pid               # PID files
└── <name>.log               # Log files
```

## Configuration

Create a config file in `~/.config/rustunnl/<name>.env`:

```bash
# Target SSH connection
TARGET_HOST="user@remote-server.com"
SSH_KEY="$HOME/.ssh/id_ed25519_tunnel"

# Tunnel mapping (Remote:Local)
REMOTE_PORT=33000
LOCAL_TARGET="192.168.1.10:3000"

# Keep-alive settings
KEEPALIVE_INTERVAL=30
KEEPALIVE_COUNT_MAX=3

# Optional: Description
DESCRIPTION="Remote server → Local service"
```

## Usage

### Fish Function

```fish
rustunnl start <name>     # Start tunnel
rustunnl stop <name>      # Stop tunnel (complete cleanup)
rustunnl status [name]    # Show status
rustunnl restart <name>   # Restart tunnel
rustunnl list             # List all configured tunnels
```

### Examples

```fish
# Setup
cp examples/tunnel-config.example ~/.config/rustunnl/mytunnel.env
micro ~/.config/rustunnl/mytunnel.env

# Manage tunnel
rustunnl start mytunnel
rustunnl status mytunnel
rustunnl stop mytunnel
```

## How It Works

1. Reads config from `~/.config/rustunnl/<name>.env`
2. Starts `autossh` with reverse tunnel (`-R`)
3. Remote server port forwards to local target
4. Auto-reconnects on connection loss
5. Tracks PID and logs in `~/.local/state/rustunnl/`

## Example Use Case

**Problem:** External VPS needs to access local development server behind NAT.

**Solution:**
```
Local Machine (behind NAT)
  ↓ SSH Tunnel
Remote VPS
  ↓ localhost:33000
Local Service (192.168.1.x:3000)
```

Remote VPS accesses `http://localhost:33000/` which tunnels to local service.

## Deployment

Deploy to remote machines via SCP:

```bash
scp -r /path/to/rustunnl/ user@remote:/path/to/destination/
```

## Future: Rust Refactor

This will be rewritten in Rust as a proper binary while maintaining:
- Same XDG directory structure
- Same config format
- Same Fish function interface
- Better error handling and logging

## Security Notes

- SSH keys are gitignored
- Config files (may contain IPs/hostnames) are gitignored
- Use dedicated SSH keys for tunnels
- Consider using `authorized_keys` restrictions on remote server

## License

MIT License - Open Source
