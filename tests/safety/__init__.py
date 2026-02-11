"""Safety feature tests for Claude Code.

This package contains tests for the destructive command safety features:
- Intent recognition: distinguishing "show me the command" vs "run the command"
- Destructive command detection: identifying dangerous commands like rm -rf
- Accept Edits override: ensuring safety prompts even with auto-approve enabled
- File reference handling: clarifying ambiguous file references
"""
