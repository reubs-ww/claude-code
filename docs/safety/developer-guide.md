# Safety System Developer Guide

This guide explains the architecture of Claude Code's safety features and how to extend them.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Hook System](#hook-system)
3. [Adding New Safety Patterns](#adding-new-safety-patterns)
4. [Testing Safety Features](#testing-safety-features)
5. [Best Practices](#best-practices)

## Architecture Overview

The safety system consists of several layers:

```
┌─────────────────────────────────────────────────────────────┐
│                    User Request                              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Intent Recognition Layer                        │
│  (Distinguishes "show me" vs "run" commands)                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Permission Mode Check                           │
│  (ask, accept, deny)                                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              PreToolUse Hooks                                │
│  ├── hookify (configurable rules)                           │
│  └── security-guidance (hardcoded patterns)                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Tool Execution                                  │
│  (Bash, Edit, Write, etc.)                                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              PostToolUse Hooks                               │
│  (Logging, validation, etc.)                                │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Hookify Plugin | `plugins/hookify/` | Configurable rule-based hooks |
| Security Guidance | `plugins/security-guidance/` | Hardcoded security patterns |
| Config Loader | `plugins/hookify/core/config_loader.py` | Loads rule files |
| Rule Engine | `plugins/hookify/core/rule_engine.py` | Evaluates rules against input |
| Safety Tests | `tests/safety/` | Automated testing |

## Hook System

Claude Code uses hooks to intercept operations at various points.

### Hook Event Types

| Event | When Fired | Use Case |
|-------|------------|----------|
| `PreToolUse` | Before any tool executes | Block/warn before action |
| `PostToolUse` | After tool completes | Log/validate results |
| `Stop` | When Claude wants to stop | Ensure tasks are complete |
| `UserPromptSubmit` | User submits a prompt | Transform/validate input |
| `SessionStart` | Session begins | Load context |
| `SessionEnd` | Session ends | Cleanup |

### Hook Input Format

Hooks receive JSON via stdin:

```json
{
  "session_id": "abc-123",
  "transcript_path": "/path/to/transcript.txt",
  "cwd": "/current/working/directory",
  "permission_mode": "ask",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm -rf /tmp/test"
  }
}
```

### Hook Output Format

Hooks output JSON via stdout:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny"
  },
  "systemMessage": "Operation blocked: rm -rf is destructive"
}
```

### Exit Codes

| Exit Code | Meaning |
|-----------|---------|
| 0 | Allow operation |
| 1 | Error (show to user, allow operation) |
| 2 | Block operation (show message to Claude) |

## Adding New Safety Patterns

### Option 1: Hookify Rules (Recommended)

Create a rule file in `.claude/hookify.*.local.md`:

```markdown
---
name: block-fork-bomb
enabled: true
event: bash
pattern: :\(\)\s*{\s*:\|:\s*&\s*};
action: block
---

Fork bomb detected! This command would crash your system.
```

### Option 2: Code-Based Patterns

For patterns requiring logic, add to `plugins/hookify/core/`:

```python
# In rule_engine.py or new file

class CustomMatcher:
    """Custom pattern matcher with complex logic."""

    def matches(self, command: str, context: dict) -> bool:
        """Check if command matches this pattern.

        Args:
            command: The command string
            context: Additional context (cwd, session, etc.)

        Returns:
            True if pattern matches
        """
        # Complex matching logic here
        if self._is_in_sensitive_directory(context.get('cwd', '')):
            if 'rm' in command:
                return True
        return False

    def _is_in_sensitive_directory(self, path: str) -> bool:
        sensitive = ['/etc', '/usr', '/var', '/root']
        return any(path.startswith(s) for s in sensitive)
```

### Option 3: Security Guidance Plugin

For patterns that should always be active, add to `plugins/security-guidance/`:

```python
# In security_reminder_hook.py

SECURITY_PATTERNS.append({
    "ruleName": "fork_bomb_detection",
    "substrings": [":()", "{ :|: & }"],
    "reminder": "Fork bomb pattern detected. This could crash your system."
})
```

## Testing Safety Features

### Test Structure

```
tests/
└── safety/
    ├── __init__.py              # Package init
    ├── conftest.py              # Shared fixtures
    ├── test_intent_recognition.py
    ├── test_destructive_commands.py
    ├── test_accept_edits_override.py
    └── test_file_reference.py
```

### Running Tests

```bash
# Install pytest if needed
pip install pytest

# Run all safety tests
pytest tests/safety/ -v

# Run specific test file
pytest tests/safety/test_destructive_commands.py -v

# Run with coverage
pytest tests/safety/ --cov=plugins/hookify/core
```

### Writing New Tests

Use the fixtures from `conftest.py`:

```python
def test_new_pattern_is_blocked(hookify_rule_engine, create_rule_file):
    """Test that the new pattern is properly blocked."""
    from tests.safety.conftest import create_bash_input

    # Create a rule
    create_rule_file(
        name="block-new-pattern",
        event="bash",
        pattern=r"dangerous_command",
        action="block",
        message="This pattern is blocked"
    )

    # Load rules
    from hookify.core.config_loader import load_rules
    rules = load_rules(event="bash")

    # Test matching input
    input_data = create_bash_input("dangerous_command --force")
    result = hookify_rule_engine.evaluate_rules(rules, input_data)

    # Verify blocked
    assert 'hookSpecificOutput' in result
    hook_output = result.get('hookSpecificOutput', {})
    assert hook_output.get('permissionDecision') == 'deny'
```

### Testing Hooks Directly

Use the `test-hook.sh` script:

```bash
# Create sample input
./plugins/plugin-dev/skills/hook-development/scripts/test-hook.sh \
    --create-sample PreToolUse > /tmp/test-input.json

# Edit the input file with your test case
# ...

# Run the hook
./plugins/plugin-dev/skills/hook-development/scripts/test-hook.sh \
    plugins/hookify/hooks/pretooluse.py \
    /tmp/test-input.json
```

## Best Practices

### 1. Pattern Design

**Do:**
- Use specific patterns that match the dangerous operation
- Consider edge cases and variations
- Test with real-world command examples

**Don't:**
- Create overly broad patterns that block safe operations
- Forget about command flags and options
- Ignore case sensitivity when appropriate

### 2. Error Handling

```python
def evaluate_rule(self, rule, input_data):
    try:
        # Rule evaluation logic
        return self._check_pattern(rule, input_data)
    except re.error as e:
        # Log the error but don't crash
        print(f"Invalid regex in rule {rule.name}: {e}", file=sys.stderr)
        return False  # Fail open for rule errors
    except Exception as e:
        # Unexpected errors - fail open to not block users
        print(f"Error in rule {rule.name}: {e}", file=sys.stderr)
        return False
```

### 3. Message Quality

Good messages:
- Explain what was detected
- Suggest safer alternatives
- Are concise but informative

```markdown
---
name: warn-chmod-777
message: |
  ⚠️ **Dangerous permissions detected**

  `chmod 777` makes files readable/writable/executable by everyone.

  Consider using more restrictive permissions:
  - `chmod 755` for executables
  - `chmod 644` for regular files
  - `chmod 600` for sensitive files
---
```

### 4. Performance

- Compile regex patterns once (use `lru_cache`)
- Load rules once per session, not per tool use
- Keep pattern matching simple and fast

```python
from functools import lru_cache

@lru_cache(maxsize=128)
def compile_pattern(pattern: str) -> re.Pattern:
    """Compile regex with caching."""
    return re.compile(pattern, re.IGNORECASE)
```

### 5. Testing Checklist

For every new safety pattern, test:

- [ ] Pattern matches the dangerous command
- [ ] Pattern does NOT match similar safe commands
- [ ] Pattern works with different flag orders
- [ ] Pattern works with different argument formats
- [ ] Blocking/warning behavior is correct
- [ ] Message is helpful and accurate
- [ ] Pattern works in Accept Edits mode
- [ ] Edge cases are handled

## Related Documentation

- [Hookify Plugin README](../../plugins/hookify/README.md)
- [Security Guidance Plugin](../../plugins/security-guidance/)
- [Hook Development Skill](../../plugins/plugin-dev/skills/hook-development/)
- [User Guide](./user-guide.md)

## Contributing

When adding new safety features:

1. Create tests first (TDD approach)
2. Implement the feature
3. Document the change
4. Submit for review

For questions or discussions, open an issue or reach out on Discord.
