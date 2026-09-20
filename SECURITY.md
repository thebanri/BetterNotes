# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Threat Model & Security Principles

BetterNotes is an offline-first desktop application that places strict boundaries around user data and external inputs:

1. **Untrusted External Inputs:**
   - Note contents, imported files, and IPC messages are treated as untrusted data.
   - Note content is never executed as shell or system commands.
2. **Path Traversal & Filesystem Safety:**
   - Attachments and export/import operations sanitize paths to prevent directory traversal attacks outside of `$XDG_DATA_HOME/betternotes/`.
3. **Local IPC Isolation:**
   - The IPC Unix Domain Socket is created within the user's private runtime directory (`$XDG_RUNTIME_DIR/betternotes/`) with `0700` filesystem permissions, preventing unauthorized access by other local users on multi-user systems.
   - IPC messages are restricted to a 1 MiB hard ceiling to prevent denial-of-service or memory exhaustion.
4. **Zero Telemetry & Privacy First:**
   - BetterNotes never connects to remote analytics, advertising, or cloud servers.
   - All persistence resides strictly on the local machine in SQLite databases.

## Reporting a Vulnerability

If you discover a security vulnerability in BetterNotes, please report it responsibly:

- **Email:** Open a private security advisory on GitHub or email the maintainers directly.
- Please do NOT disclose vulnerabilities publicly in issues or pull requests until a patch has been made available.
- Include a description of the issue, reproduction steps, and potential impact.
- Maintainers aim to acknowledge reports within 48 hours and provide updates on resolution progress.
