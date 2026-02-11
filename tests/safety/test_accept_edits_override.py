"""Tests for Accept Edits override behavior.

This module tests that destructive command safety checks are NOT bypassed
by the "Accept Edits" permission mode.

The safety principle is:
- Accept Edits mode auto-approves file edits and safe commands
- Accept Edits mode should STILL prompt for destructive commands
- Destructive operations require explicit user confirmation regardless of mode

Permission modes:
- "ask": Always prompt for confirmation (default)
- "accept": Auto-approve (Accept Edits mode)
- "deny": Always deny (safety lockdown)
"""

import pytest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "plugins"))


class AcceptEditsPolicy:
    """Policy engine for Accept Edits mode behavior.

    This class determines what gets auto-approved in Accept Edits mode
    and what still requires explicit confirmation.
    """

    # Commands that are ALWAYS safe to auto-approve in Accept Edits mode
    AUTO_APPROVE_PATTERNS = [
        r'^ls\b',
        r'^cat\b',
        r'^head\b',
        r'^tail\b',
        r'^grep\b',
        r'^find\b.*-print',
        r'^pwd\b',
        r'^echo\b(?!.*>)',  # echo without redirection
        r'^whoami\b',
        r'^date\b',
        r'^wc\b',
    ]

    # Commands that NEVER get auto-approved, even in Accept Edits mode
    # These are the destructive commands that override Accept Edits
    NEVER_AUTO_APPROVE = [
        r'\brm\b',           # Any rm command
        r'\bdd\b',           # dd command
        r'\bmkfs\b',         # Format filesystem
        r'\bformat\b',       # Format command
        r'\bdrop\b',         # SQL drop
        r'\btruncate\b',     # Truncate
        r'\bkill\b',         # Kill processes
        r'\bchmod\s+777\b',  # Dangerous permissions
        r'\breboot\b',       # System reboot
        r'\bshutdown\b',     # System shutdown
        r'\bsudo\b',         # Any sudo command (requires extra scrutiny)
    ]

    def __init__(self):
        """Initialize the policy with compiled patterns."""
        import re
        self._auto_approve = [
            re.compile(p, re.IGNORECASE) for p in self.AUTO_APPROVE_PATTERNS
        ]
        self._never_approve = [
            re.compile(p, re.IGNORECASE) for p in self.NEVER_AUTO_APPROVE
        ]

    def should_auto_approve(
        self,
        command: str,
        permission_mode: str = "ask"
    ) -> tuple[bool, str]:
        """Determine if a command should be auto-approved.

        Args:
            command: The bash command to check
            permission_mode: Current permission mode ("ask", "accept", "deny")

        Returns:
            Tuple of (should_auto_approve, reason)
        """
        command = command.strip()

        # If mode is "ask" or "deny", never auto-approve
        if permission_mode == "ask":
            return False, "Permission mode requires asking"

        if permission_mode == "deny":
            return False, "Permission mode denies all"

        # In "accept" mode, check against never-approve patterns first
        for pattern in self._never_approve:
            if pattern.search(command):
                return False, f"Destructive command overrides Accept Edits"

        # Check if it's an explicitly safe command
        for pattern in self._auto_approve:
            if pattern.match(command):
                return True, "Safe command in Accept Edits mode"

        # Default: prompt for confirmation even in Accept Edits mode
        # This is the conservative approach - only explicitly safe commands
        # get auto-approved
        return False, "Command not in safe list"

    def get_effective_permission_mode(
        self,
        command: str,
        base_mode: str
    ) -> str:
        """Get the effective permission mode for a command.

        Even if base_mode is "accept", destructive commands get "ask".

        Args:
            command: The command to execute
            base_mode: The user's configured permission mode

        Returns:
            Effective permission mode to use
        """
        if base_mode != "accept":
            return base_mode

        # Check if this command overrides Accept Edits
        for pattern in self._never_approve:
            if pattern.search(command):
                return "ask"  # Force asking for destructive commands

        return "accept"


class TestAcceptEditsOverride:
    """Tests for Accept Edits override behavior."""

    @pytest.fixture
    def policy(self):
        """Create a policy instance."""
        return AcceptEditsPolicy()

    # ==================== Accept Edits ON + Destructive ====================

    @pytest.mark.parametrize("command", [
        "rm file.txt",
        "rm -rf /tmp/test",
        "rm -f important.doc",
    ])
    def test_rm_still_prompts_with_accept_edits(self, policy, command):
        """rm commands should prompt even with Accept Edits enabled."""
        auto_approve, reason = policy.should_auto_approve(
            command, permission_mode="accept"
        )
        assert not auto_approve, (
            f"rm should NOT be auto-approved in Accept Edits: {command}"
        )
        assert "Destructive" in reason or "override" in reason.lower()

    @pytest.mark.parametrize("command", [
        "dd if=/dev/zero of=/dev/sda",
        "dd if=image.iso of=/dev/disk2",
    ])
    def test_dd_still_prompts_with_accept_edits(self, policy, command):
        """dd commands should prompt even with Accept Edits enabled."""
        auto_approve, _ = policy.should_auto_approve(
            command, permission_mode="accept"
        )
        assert not auto_approve, (
            f"dd should NOT be auto-approved in Accept Edits: {command}"
        )

    @pytest.mark.parametrize("command", [
        "sudo rm -rf /var/log",
        "sudo apt-get remove",
        "sudo mkfs.ext4 /dev/sda1",
    ])
    def test_sudo_still_prompts_with_accept_edits(self, policy, command):
        """sudo commands should prompt even with Accept Edits enabled."""
        auto_approve, _ = policy.should_auto_approve(
            command, permission_mode="accept"
        )
        assert not auto_approve, (
            f"sudo should NOT be auto-approved in Accept Edits: {command}"
        )

    @pytest.mark.parametrize("command", [
        "kill -9 1234",
        "killall python",
    ])
    def test_kill_still_prompts_with_accept_edits(self, policy, command):
        """kill commands should prompt even with Accept Edits enabled."""
        auto_approve, _ = policy.should_auto_approve(
            command, permission_mode="accept"
        )
        assert not auto_approve, (
            f"kill should NOT be auto-approved in Accept Edits: {command}"
        )

    # ==================== Accept Edits ON + Safe Commands ====================

    @pytest.mark.parametrize("command", [
        "ls",
        "ls -la",
        "cat file.txt",
        "head -n 10 file.txt",
        "tail -f log.txt",
        "grep pattern file.txt",
        "pwd",
        "whoami",
        "date",
        "wc -l file.txt",
    ])
    def test_safe_commands_auto_approve_with_accept_edits(self, policy, command):
        """Safe commands should auto-approve with Accept Edits enabled."""
        auto_approve, reason = policy.should_auto_approve(
            command, permission_mode="accept"
        )
        assert auto_approve, (
            f"Safe command should auto-approve in Accept Edits: {command}"
        )
        assert "Safe" in reason or "accept" in reason.lower()

    # ==================== Accept Edits OFF (Normal Behavior) ====================

    @pytest.mark.parametrize("command", [
        "ls",
        "rm file.txt",
        "cat file.txt",
    ])
    def test_ask_mode_never_auto_approves(self, policy, command):
        """With permission_mode='ask', nothing is auto-approved."""
        auto_approve, _ = policy.should_auto_approve(
            command, permission_mode="ask"
        )
        assert not auto_approve, (
            f"Nothing should auto-approve in 'ask' mode: {command}"
        )

    @pytest.mark.parametrize("command", [
        "ls",
        "rm file.txt",
        "cat file.txt",
    ])
    def test_deny_mode_never_auto_approves(self, policy, command):
        """With permission_mode='deny', nothing is auto-approved."""
        auto_approve, _ = policy.should_auto_approve(
            command, permission_mode="deny"
        )
        assert not auto_approve, (
            f"Nothing should auto-approve in 'deny' mode: {command}"
        )


class TestEffectivePermissionMode:
    """Tests for effective permission mode calculation."""

    @pytest.fixture
    def policy(self):
        """Create a policy instance."""
        return AcceptEditsPolicy()

    def test_destructive_command_forces_ask_mode(self, policy):
        """Destructive commands should force 'ask' mode even if base is 'accept'."""
        # rm forces ask
        assert policy.get_effective_permission_mode("rm file.txt", "accept") == "ask"
        # dd forces ask
        assert policy.get_effective_permission_mode("dd if=x of=y", "accept") == "ask"
        # kill forces ask
        assert policy.get_effective_permission_mode("kill -9 123", "accept") == "ask"

    def test_safe_command_respects_accept_mode(self, policy):
        """Safe commands should respect 'accept' mode."""
        assert policy.get_effective_permission_mode("ls", "accept") == "accept"
        assert policy.get_effective_permission_mode("cat f.txt", "accept") == "accept"
        assert policy.get_effective_permission_mode("pwd", "accept") == "accept"

    def test_ask_mode_is_preserved(self, policy):
        """'ask' mode should always be preserved."""
        assert policy.get_effective_permission_mode("ls", "ask") == "ask"
        assert policy.get_effective_permission_mode("rm file", "ask") == "ask"

    def test_deny_mode_is_preserved(self, policy):
        """'deny' mode should always be preserved."""
        assert policy.get_effective_permission_mode("ls", "deny") == "deny"
        assert policy.get_effective_permission_mode("rm file", "deny") == "deny"


class TestHookifyAcceptEditsIntegration:
    """Test hookify integration with Accept Edits mode."""

    def test_block_action_ignores_permission_mode(
        self, hookify_rule_engine, create_rule_file
    ):
        """Block action should work regardless of permission mode."""
        from tests.safety.conftest import create_bash_input

        # Create a blocking rule
        create_rule_file(
            name="block-rm",
            event="bash",
            pattern=r"rm\s+",
            action="block",
            message="rm commands are blocked"
        )

        from hookify.core.config_loader import load_rules
        rules = load_rules(event="bash")

        # Test with Accept Edits mode
        input_data = create_bash_input(
            "rm file.txt",
            permission_mode="accept"
        )
        result = hookify_rule_engine.evaluate_rules(rules, input_data)

        # Should still be blocked
        assert result != {}, "Block should work even with Accept Edits"
        # Check for deny in hook output
        hook_output = result.get('hookSpecificOutput', {})
        if hook_output:
            assert hook_output.get('permissionDecision') == 'deny'

    def test_warn_action_shows_message_in_accept_mode(
        self, hookify_rule_engine, create_rule_file
    ):
        """Warn action should show message even in Accept Edits mode."""
        from tests.safety.conftest import create_bash_input

        # Create a warning rule
        create_rule_file(
            name="warn-rm",
            event="bash",
            pattern=r"rm\s+",
            action="warn",
            message="Warning: rm command detected"
        )

        from hookify.core.config_loader import load_rules
        rules = load_rules(event="bash")

        # Test with Accept Edits mode
        input_data = create_bash_input(
            "rm file.txt",
            permission_mode="accept"
        )
        result = hookify_rule_engine.evaluate_rules(rules, input_data)

        # Should have a system message warning
        assert 'systemMessage' in result, "Warning should still show in Accept Edits"


class TestFileEditSafetyInAcceptMode:
    """Test file edit operations in Accept Edits mode."""

    def test_security_pattern_blocks_in_accept_mode(
        self, hookify_rule_engine, create_rule_file
    ):
        """Security patterns should still trigger in Accept Edits mode."""
        from tests.safety.conftest import create_write_input

        # Create a rule to warn about eval
        create_rule_file(
            name="warn-eval",
            event="file",
            conditions=[{
                "field": "content",
                "operator": "regex_match",
                "pattern": r"eval\("
            }],
            action="warn",
            message="Warning: eval() detected in file"
        )

        from hookify.core.config_loader import load_rules
        rules = load_rules(event="file")

        # Test with Accept Edits mode
        input_data = create_write_input(
            file_path="/tmp/test.py",
            content="result = eval(user_input)",
            permission_mode="accept"
        )
        result = hookify_rule_engine.evaluate_rules(rules, input_data)

        # Should have warning message
        assert 'systemMessage' in result, "Security warning should show in Accept mode"

    def test_safe_file_edits_pass_in_accept_mode(
        self, hookify_rule_engine, create_rule_file
    ):
        """Safe file edits should pass through in Accept Edits mode."""
        from tests.safety.conftest import create_write_input

        # Create a rule that only matches dangerous content
        create_rule_file(
            name="warn-eval",
            event="file",
            conditions=[{
                "field": "content",
                "operator": "regex_match",
                "pattern": r"eval\("
            }],
            action="warn",
            message="Warning: eval() detected"
        )

        from hookify.core.config_loader import load_rules
        rules = load_rules(event="file")

        # Test with safe content
        input_data = create_write_input(
            file_path="/tmp/test.py",
            content="print('Hello, World!')",
            permission_mode="accept"
        )
        result = hookify_rule_engine.evaluate_rules(rules, input_data)

        # Should NOT have any messages
        assert result == {}, "Safe file edit should pass without warnings"
