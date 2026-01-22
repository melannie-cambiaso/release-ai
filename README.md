# release-ai

**Automated release management with Claude AI integration**

A powerful CLI tool that automates the complete software release lifecycle with intelligent AI assistance for version suggestions, release notes generation, and change validation.

## Features

### Core Release Management
- 🚀 **Automated Release Workflow** - Complete orchestration from branch creation to tagging
- 🔄 **Git Operations** - Safe wrappers with retry logic and validation
- 📝 **Version Management** - Semantic versioning with conventional commits support
- 📦 **Multi-file Updates** - Update versions in package.json, app.json, and more
- 🔙 **Rollback Support** - Safe recovery from failed releases

### Claude AI Integration (Optional)
- 🤖 **Version Suggestions** - AI analyzes commits and suggests major/minor/patch bumps
- 📄 **Release Notes Generation** - Automatically create professional release notes
- ✅ **Change Validation** - Pre-release checks for breaking changes and inconsistencies
- 💬 **Interactive Assistant** - Conversational guide through the release process

### Technical Highlights
- ✨ **100% Bash** - No Node.js runtime dependencies
- 🪶 **Lightweight** - Only requires: `bash`, `git`, `gh`, `jq`, `curl`
- ⚙️ **Configurable** - Hierarchical config system (env vars → project → global)
- 🔒 **Secure** - API keys stored with proper permissions, never in code
- 📦 **Easy Install** - Homebrew formula or simple install script

## Installation

### Homebrew (Recommended)

```bash
brew tap melannie-cambiaso/release-ai https://github.com/melannie-cambiaso/release-ai
brew install release-ai
```

### Manual Installation

```bash
git clone https://github.com/melannie-cambiaso/release-ai.git
cd release-ai
./install.sh
```

The script will:
- Install the binary to `/usr/local/bin` or `~/.local/bin`
- Copy libraries to `~/.local/share/release-ai/`
- Set up proper permissions

### Verify Installation

```bash
release-ai version
# release-ai v1.0.0
```

## Quick Start

### 1. Initialize in Your Project

```bash
cd your-project
release-ai init
```

This creates `.release-ai.config.json` and optionally sets up your Claude API key.

### 2. Configure (Optional)

Edit `.release-ai.config.json`:

```json
{
  "main_branch": "main",
  "develop_branch": "develop",
  "pr_target_branch": "main",
  "version_files": [
    {
      "path": "package.json",
      "field": "version"
    }
  ],
  "ai_features": {
    "auto_suggest_version": true,
    "generate_notes": true,
    "validate_changes": true
  }
}
```

### 3. Create a Release

#### Traditional (Manual Version)

```bash
release-ai start 1.2.0
release-ai merge
release-ai finalize
```

#### AI-Assisted (Automatic)

```bash
# Ask Claude to suggest the next version
release-ai suggest

# Start release with AI suggestion
release-ai start --auto

# Validate changes with AI
release-ai validate

# Generate release notes with AI
release-ai notes 1.2.0

# Complete the release
release-ai merge
release-ai finalize
```

## Commands

### Release Commands

| Command | Description |
|---------|-------------|
| `release-ai start <version>` | Create release branch and PR |
| `release-ai start --auto` | Auto-suggest version with Claude AI |
| `release-ai merge` | Prepare merge with main branch |
| `release-ai finalize` | Create tag and complete release |
| `release-ai rollback` | Rollback failed release |

### AI Commands (Requires Claude API Key)

| Command | Description |
|---------|-------------|
| `release-ai suggest` | Claude suggests next version based on commits |
| `release-ai notes <version>` | Generate release notes with Claude |
| `release-ai validate` | Claude validates changes pre-release |
| `release-ai assist` | Interactive Claude assistant |

### Utility Commands

| Command | Description |
|---------|-------------|
| `release-ai init` | Initialize release-ai in current project |
| `release-ai config` | Show current configuration |
| `release-ai version` | Show version |
| `release-ai help` | Show help message |

## Configuration

### Configuration Hierarchy

release-ai uses a hierarchical configuration system with the following priority:

1. **Environment variables** (highest priority)
2. **Project config** (`.release-ai.config.json`)
3. **Global config** (`~/.config/release-ai/config.json`)
4. **Default values** (lowest priority)

### Global Configuration

Located at `~/.config/release-ai/config.json`:

```json
{
  "anthropic_api_key": "sk-ant-...",
  "claude": {
    "model": "claude-sonnet-4-5-20250929"
  }
}
```

**Security**: This file should have `600` permissions (readable only by you).

### Project Configuration

Located at `.release-ai.config.json` in your project root:

```json
{
  "main_branch": "main",
  "develop_branch": "develop",
  "pr_target_branch": "main",
  "version_files": [
    {
      "path": "package.json",
      "field": "version"
    },
    {
      "path": "app.json",
      "field": "expo.version"
    }
  ],
  "release_notes_dir": ".releases",
  "ai_features": {
    "auto_suggest_version": true,
    "generate_notes": true,
    "validate_changes": true,
    "conversational_mode": false
  },
  "commit_conventions": {
    "types": ["feat", "fix", "docs", "style", "refactor", "test", "chore"],
    "breaking_change_indicators": ["!", "BREAKING CHANGE:"]
  },
  "claude": {
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": {
      "suggest_version": 500,
      "generate_notes": 2048,
      "validate_changes": 1024,
      "assist": 1024
    }
  }
}
```

### Environment Variables

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export MAIN_BRANCH="main"
export DEVELOP_BRANCH="develop"
export PR_TARGET_BRANCH="main"
export RELEASE_AI_NO_AI=true  # Disable AI features
```

## Claude AI Features

### 1. Version Suggestion

Claude analyzes your commits following conventional commits and suggests the appropriate semantic version bump:

```bash
$ release-ai suggest
```

**Output**:
```json
{
  "bump_type": "minor",
  "suggested_version": "1.2.0",
  "reasoning": "3 new features and 2 bug fixes detected",
  "highlights": [
    "feat: Add user authentication",
    "feat: Implement dark mode",
    "fix: Resolve login bug"
  ]
}
```

### 2. Release Notes Generation

Automatically generate professional, categorized release notes:

```bash
$ release-ai notes 1.2.0
```

**Output**: Markdown file in `.releases/release-notes-1.2.0.md`

```markdown
# Release v1.2.0

## 🚀 Features
- Add user authentication with OAuth2
- Implement dark mode support
- Add export to PDF functionality

## 🐛 Bug Fixes
- Resolve login redirect issue
- Fix memory leak in data processing

## 📝 Other Changes
- Update dependencies
- Improve documentation
```

### 3. Change Validation

Pre-release checks for common issues:

```bash
$ release-ai validate
```

**Checks**:
- Breaking changes without proper documentation
- Conventional commit compliance
- Code changes without associated tests
- Debug code (console.log, debugger) in production
- Version consistency across files

### 4. Interactive Assistant

Conversational AI guide for releases:

```bash
$ release-ai assist

¿En qué puedo ayudarte con tu release?
Tú: Should I create a major or minor release?
Claude: Based on your recent commits, I recommend a minor release (1.2.0)...
```

### API Costs

Estimated costs per release using Claude Sonnet 4.5:
- **suggest-version**: ~$0.005
- **generate-notes**: ~$0.014
- **validate**: ~$0.014

**Total per release**: ~$0.03 USD

## Complete Workflow Example

### Scenario: Releasing v1.2.0

```bash
# 1. Initialize (first time only)
cd my-project
release-ai init

# 2. Make your changes and commit following conventional commits
git commit -m "feat: add user profile page"
git commit -m "fix: resolve authentication bug"
git commit -m "feat: implement search functionality"

# 3. Let Claude suggest the version
release-ai suggest
# Suggests: v1.2.0 (minor) - 2 features, 1 fix

# 4. Validate changes before release
release-ai validate
# ✓ All checks passed

# 5. Start the release (AI-assisted)
release-ai start --auto
# Creates branch: release-1.2.0
# Updates versions in package.json, app.json
# Creates PR

# 6. Generate release notes
release-ai notes 1.2.0
# Creates: .releases/release-notes-1.2.0.md

# 7. After PR review, merge to main
release-ai merge
# Merges with main using 'ours' strategy

# 8. Finalize the release
release-ai finalize
# Creates tag: v1.2.0
# Pushes to remote

# Done! 🎉
```

## Troubleshooting

### "API key not configured"

**Solution**: Set your API key in global config:

```bash
echo '{"anthropic_api_key": "sk-ant-..."}' > ~/.config/release-ai/config.json
chmod 600 ~/.config/release-ai/config.json
```

Or use environment variable:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

### "Command not found: release-ai"

**Solution**: Ensure the install directory is in your PATH:

```bash
# Add to ~/.bashrc or ~/.zshrc
export PATH="/usr/local/bin:$PATH"
# or
export PATH="$HOME/.local/bin:$PATH"
```

### "gh CLI not authenticated"

**Solution**: Authenticate with GitHub CLI:

```bash
gh auth login
```

### "Permission denied"

**Solution**: Fix installation directory permissions:

```bash
sudo chown -R $(whoami) /usr/local/bin
```

## Uninstallation

```bash
./uninstall.sh
```

Or manually:

```bash
rm -f /usr/local/bin/release-ai
rm -rf ~/.local/share/release-ai
rm -rf ~/.config/release-ai  # Optional: removes API key
```

## Development

### Project Structure

```
release-ai/
├── bin/
│   └── release-ai              # CLI entry point
├── lib/
│   ├── logging.sh              # Logging & config system
│   ├── version-manager.sh      # Semantic versioning
│   ├── git-operations.sh       # Git wrappers
│   ├── json-updater.sh         # JSON manipulation
│   └── claude-integration.sh   # AI integration (curl)
├── templates/
│   └── release-notes.md.template
├── install.sh
├── uninstall.sh
└── README.md
```

### Running Locally

```bash
# From repo root
./bin/release-ai version
./bin/release-ai init

# Or add to PATH temporarily
export PATH="$(pwd)/bin:$PATH"
release-ai version
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details

## Credits

- Inspired by [gentleman-guardian-angel](https://github.com/Gentleman-Programming/gentleman-guardian-angel)
- Powered by [Claude AI](https://claude.ai) from Anthropic

## Support

- 📖 [Documentation](https://github.com/melannie-cambiaso/release-ai)
- 🐛 [Report Issues](https://github.com/melannie-cambiaso/release-ai/issues)
- 💬 [Discussions](https://github.com/melannie-cambiaso/release-ai/discussions)

---

Made with ❤️ by the release-ai team
