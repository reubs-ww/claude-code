"""Pytest configuration and fixtures for safety tests."""

import os
import sys
import pytest
import json
import tempfile
from pathlib import Path
from typing import Dict, Any, Optional

# Add plugin paths for imports
REPO_ROOT = Path(__file__).parent.parent.parent
HOOKIFY_PLUGIN = REPO_ROOT / "plugins" / "hookify"

sys.path.insert(0, str(REPO_ROOT / "plugins"))


@pytest.fixture
def hookify_rule_engine():
    """Get the hookify rule engine for testing."""
    from hookify.core.rule_engine import RuleEngine
    return RuleEngine()


@pytest.fixture
def hookify_config_loader():
    """Get the hookify config loader module."""
    from hookify.core import config_loader
    return config_loader


@pytest.fixture
def temp_claude_dir(tmp_path):
    """Create a temporary .claude directory for rule files."""
    claude_dir = tmp_path / ".claude"
    claude_dir.mkdir()

    # Change to temp directory for testing
    original_cwd = os.getcwd()
    os.chdir(tmp_path)

    yield claude_dir

    # Restore original directory
    os.chdir(original_cwd)


def create_hook_input(
    tool_name: str,
    tool_input: Dict[str, Any],
    hook_event: str = "PreToolUse",
    session_id: str = "test-session",
    permission_mode: str = "ask"
) -> Dict[str, Any]:
    """Create a hook input dictionary for testing.

    Args:
        tool_name: Name of the tool (e.g., "Bash", "Edit", "Write")
        tool_input: Tool-specific input parameters
        hook_event: Hook event name (e.g., "PreToolUse", "PostToolUse", "Stop")
        session_id: Session identifier
        permission_mode: Permission mode ("ask", "accept", etc.)

    Returns:
        Dictionary formatted as hook input
    """
    return {
        "session_id": session_id,
        "transcript_path": "/tmp/test-transcript.txt",
        "cwd": "/tmp/test-project",
        "permission_mode": permission_mode,
        "hook_event_name": hook_event,
        "tool_name": tool_name,
        "tool_input": tool_input
    }


def create_bash_input(command: str, **kwargs) -> Dict[str, Any]:
    """Convenience function to create Bash tool input.

    Args:
        command: The bash command to test
        **kwargs: Additional arguments passed to create_hook_input

    Returns:
        Dictionary formatted as hook input for Bash tool
    """
    return create_hook_input(
        tool_name="Bash",
        tool_input={"command": command},
        **kwargs
    )


def create_edit_input(
    file_path: str,
    old_string: str,
    new_string: str,
    **kwargs
) -> Dict[str, Any]:
    """Convenience function to create Edit tool input.

    Args:
        file_path: Path to the file being edited
        old_string: Original text to replace
        new_string: Replacement text
        **kwargs: Additional arguments passed to create_hook_input

    Returns:
        Dictionary formatted as hook input for Edit tool
    """
    return create_hook_input(
        tool_name="Edit",
        tool_input={
            "file_path": file_path,
            "old_string": old_string,
            "new_string": new_string
        },
        **kwargs
    )


def create_write_input(file_path: str, content: str, **kwargs) -> Dict[str, Any]:
    """Convenience function to create Write tool input.

    Args:
        file_path: Path to the file being written
        content: Content to write
        **kwargs: Additional arguments passed to create_hook_input

    Returns:
        Dictionary formatted as hook input for Write tool
    """
    return create_hook_input(
        tool_name="Write",
        tool_input={
            "file_path": file_path,
            "content": content
        },
        **kwargs
    )


def create_stop_input(reason: str, **kwargs) -> Dict[str, Any]:
    """Convenience function to create Stop event input.

    Args:
        reason: Reason for stopping
        **kwargs: Additional arguments passed to create_hook_input

    Returns:
        Dictionary formatted as hook input for Stop event
    """
    return create_hook_input(
        tool_name="",
        tool_input={},
        hook_event="Stop",
        **kwargs
    )


@pytest.fixture
def create_rule_file(temp_claude_dir):
    """Factory fixture to create hookify rule files."""

    def _create_rule(
        name: str,
        event: str,
        pattern: Optional[str] = None,
        conditions: Optional[list] = None,
        action: str = "warn",
        message: str = "Test warning message",
        enabled: bool = True
    ) -> Path:
        """Create a hookify rule file.

        Args:
            name: Rule name (used in filename)
            event: Event type (bash, file, stop, all)
            pattern: Simple pattern (mutually exclusive with conditions)
            conditions: List of condition dicts
            action: "warn" or "block"
            message: Warning/block message
            enabled: Whether rule is enabled

        Returns:
            Path to created rule file
        """
        frontmatter_lines = [
            "---",
            f"name: {name}",
            f"enabled: {'true' if enabled else 'false'}",
            f"event: {event}",
            f"action: {action}"
        ]

        if pattern:
            frontmatter_lines.append(f"pattern: {pattern}")

        if conditions:
            frontmatter_lines.append("conditions:")
            for cond in conditions:
                frontmatter_lines.append(f"  - field: {cond.get('field', 'command')}")
                frontmatter_lines.append(f"    operator: {cond.get('operator', 'regex_match')}")
                frontmatter_lines.append(f"    pattern: {cond.get('pattern', '')}")

        frontmatter_lines.append("---")
        frontmatter_lines.append("")
        frontmatter_lines.append(message)

        content = "\n".join(frontmatter_lines)

        rule_file = temp_claude_dir / f"hookify.{name}.local.md"
        rule_file.write_text(content)

        return rule_file

    return _create_rule
