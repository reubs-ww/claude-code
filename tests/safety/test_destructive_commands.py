"""Tests for destructive command detection.

This module tests the system's ability to identify dangerous commands
that should trigger confirmation before execution.

Destructive commands include:
- File deletion (rm, rm -rf)
- Disk operations (dd, mkfs, format)
- Database operations (drop, truncate)
- System-level changes (chmod 777, sudo rm)
- Network operations that could expose data

Non-destructive commands should NOT trigger confirmation:
- Read operations (ls, cat, head, tail)
- Safe writes (echo to stdout)
- Navigation (cd, pwd)
"""

import pytest
import re
import sys
from pathlib import Path

# Add plugins directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "plugins"))


class DestructiveCommandDetector:
    """Detector for potentially destructive shell commands.

    This class provides pattern-based detection of commands that could
    cause data loss, system damage, or security issues.
    """

    # Patterns for destructive file operations
    FILE_DESTRUCTIVE_PATTERNS = [
        r'\brm\s+', r'\brm$',                    # rm (any variant)
        r'\bunlink\b',                           # unlink files
        r'\bshred\b',                            # secure delete
        r'\btruncate\b',                         # truncate files
        r'\b>\s*/dev/null\b',                    # Redirect to null (potential data loss if wrong)
        r'>\s*[^|]',                             # Overwrite redirection (could destroy files)
    ]

    # Patterns for destructive disk operations
    DISK_DESTRUCTIVE_PATTERNS = [
        r'\bdd\s+if=',                           # dd (disk destroyer)
        r'\bmkfs\b',                             # Format filesystem
        r'\bformat\b',                           # Format drive
        r'\bfdisk\b',                            # Partition editor
        r'\bparted\b',                           # Partition editor
        r'\bgdisk\b',                            # GPT partition editor
    ]

    # Patterns for destructive system operations
    SYSTEM_DESTRUCTIVE_PATTERNS = [
        r'\bsudo\s+rm\b',                        # sudo rm
        r'\bchmod\s+777\b',                      # Dangerous permissions
        r'\bchown\s+.*\s+/',                     # Change ownership of system files
        r'\bkill\s+-9\b',                        # Force kill
        r'\bkillall\b',                          # Kill all processes
        r'\bpkill\b',                            # Pattern-based kill
        r'\breboot\b',                           # System reboot
        r'\bshutdown\b',                         # System shutdown
        r'\bhalt\b',                             # System halt
        r'\binit\s+0\b',                         # Shutdown via init
        r'\binit\s+6\b',                         # Reboot via init
    ]

    # Patterns for destructive database operations
    DATABASE_DESTRUCTIVE_PATTERNS = [
        r'\bdrop\s+database\b',                  # Drop database
        r'\bdrop\s+table\b',                     # Drop table
        r'\btruncate\s+table\b',                 # Truncate table
        r'\bdelete\s+from\b.*\bwhere\s+1\s*=\s*1\b',  # Delete all rows
        r'\bdelete\s+from\b(?!.*\bwhere\b)',     # Delete without where clause
        r'dropDatabase\(\)',                      # MongoDB drop database
        r'\.drop\(\)',                            # MongoDB drop collection
    ]

    # Patterns for network operations that could expose data
    NETWORK_DESTRUCTIVE_PATTERNS = [
        r'\bcurl\b.*\b-X\s*(POST|PUT|DELETE)\b',  # Modifying HTTP requests
        r'\bwget\b.*--post',                      # POST via wget
        r'\bssh\b.*rm\b',                         # Remote delete via SSH
    ]

    # Combined pattern list
    ALL_DESTRUCTIVE_PATTERNS = (
        FILE_DESTRUCTIVE_PATTERNS +
        DISK_DESTRUCTIVE_PATTERNS +
        SYSTEM_DESTRUCTIVE_PATTERNS +
        DATABASE_DESTRUCTIVE_PATTERNS +
        NETWORK_DESTRUCTIVE_PATTERNS
    )

    # Patterns for safe commands (explicitly safe)
    SAFE_PATTERNS = [
        r'^ls\b',                                # List files
        r'^cat\b',                               # Read file
        r'^head\b',                              # Read file head
        r'^tail\b',                              # Read file tail
        r'^pwd\b',                               # Print working directory
        r'^cd\b',                                # Change directory
        r'^echo\b',                              # Echo (without redirection)
        r'^grep\b',                              # Search files
        r'^find\b.*-print',                      # Find and print (safe)
        r'^wc\b',                                # Word count
        r'^diff\b',                              # Diff files
        r'^file\b',                              # File type
        r'^stat\b',                              # File statistics
        r'^which\b',                             # Find executable
        r'^whereis\b',                           # Find binary location
        r'^whoami\b',                            # Current user
        r'^date\b',                              # Current date/time
        r'^uptime\b',                            # System uptime
        r'^uname\b',                             # System info
        r'^hostname\b',                          # System hostname
    ]

    def __init__(self):
        """Initialize the detector with compiled patterns."""
        self._destructive_compiled = [
            re.compile(p, re.IGNORECASE) for p in self.ALL_DESTRUCTIVE_PATTERNS
        ]
        self._safe_compiled = [
            re.compile(p, re.IGNORECASE) for p in self.SAFE_PATTERNS
        ]

    def is_destructive(self, command: str) -> bool:
        """Check if a command is potentially destructive.

        Args:
            command: The shell command to analyze

        Returns:
            True if the command matches any destructive pattern
        """
        command = command.strip()

        # Check against destructive patterns
        for pattern in self._destructive_compiled:
            if pattern.search(command):
                return True

        return False

    def is_explicitly_safe(self, command: str) -> bool:
        """Check if a command is explicitly safe (read-only).

        Args:
            command: The shell command to analyze

        Returns:
            True if the command matches a known safe pattern
        """
        command = command.strip()

        # Check if starts with a safe command
        for pattern in self._safe_compiled:
            if pattern.match(command):
                return True

        return False

    def get_risk_level(self, command: str) -> str:
        """Get the risk level of a command.

        Args:
            command: The shell command to analyze

        Returns:
            'critical' - Definitely destructive, could cause major damage
            'high' - Likely destructive, should confirm
            'medium' - Potentially risky, might want to confirm
            'low' - Likely safe, no confirmation needed
            'safe' - Explicitly safe command
        """
        command = command.strip()

        if self.is_explicitly_safe(command):
            return 'safe'

        # Check for critical patterns
        critical_patterns = [
            r'\brm\s+-rf\s+/',          # rm -rf with absolute path
            r'\bdd\s+if=/dev/zero\b',   # dd zeroing
            r'\bmkfs\b',                 # Format filesystem
            r'\bdrop\s+database\b',      # Drop database
            r'\bsudo\s+rm\s+-rf\b',      # sudo rm -rf
        ]
        for pattern in critical_patterns:
            if re.search(pattern, command, re.IGNORECASE):
                return 'critical'

        # Check for high-risk patterns
        high_patterns = [
            r'\brm\s+-rf\b',            # rm -rf without path check
            r'\bdd\s+if=',              # Any dd operation
            r'\btruncate\b',            # Truncate files
            r'\bkill\s+-9\b',           # Force kill
        ]
        for pattern in high_patterns:
            if re.search(pattern, command, re.IGNORECASE):
                return 'high'

        # Check general destructive
        if self.is_destructive(command):
            return 'medium'

        return 'low'


class TestDestructiveCommandDetection:
    """Tests for destructive command detection."""

    @pytest.fixture
    def detector(self):
        """Create a detector instance."""
        return DestructiveCommandDetector()

    # ==================== rm command tests ====================

    @pytest.mark.parametrize("command", [
        "rm file.txt",
        "rm -f file.txt",
        "rm -r directory/",
        "rm -rf directory/",
        "rm -rf /tmp/test",
        "rm -rf --no-preserve-root /",
        "sudo rm -rf /var/log",
    ])
    def test_rm_triggers_confirmation(self, detector, command):
        """All variants of rm should trigger confirmation."""
        assert detector.is_destructive(command), (
            f"rm command should be destructive: {command}"
        )

    @pytest.mark.parametrize("command", [
        "rm -rf /",
        "rm -rf /*",
        "sudo rm -rf /",
        "rm -rf /home",
        "rm -rf /var",
    ])
    def test_rm_critical_paths(self, detector, command):
        """rm on critical paths should be critical risk."""
        risk = detector.get_risk_level(command)
        assert risk in ['critical', 'high'], (
            f"rm on critical path should be critical/high: {command}"
        )

    # ==================== dd command tests ====================

    @pytest.mark.parametrize("command", [
        "dd if=/dev/zero of=/dev/sda",
        "dd if=/dev/urandom of=/dev/sdb",
        "dd if=image.iso of=/dev/disk2",
        "dd if=/dev/null of=file bs=1M count=100",
    ])
    def test_dd_triggers_confirmation(self, detector, command):
        """dd (disk destroyer) should always trigger confirmation."""
        assert detector.is_destructive(command), (
            f"dd command should be destructive: {command}"
        )
        risk = detector.get_risk_level(command)
        assert risk in ['critical', 'high'], (
            f"dd command should be high risk: {command}"
        )

    # ==================== Safe command tests ====================

    @pytest.mark.parametrize("command", [
        "ls",
        "ls -la",
        "ls -la /tmp",
        "cat file.txt",
        "cat -n file.txt",
        "head file.txt",
        "head -n 10 file.txt",
        "tail file.txt",
        "tail -f log.txt",
        "pwd",
        "cd /tmp",
        "echo hello",
        "echo $PATH",
        "grep pattern file.txt",
        "wc -l file.txt",
        "diff file1.txt file2.txt",
        "whoami",
        "date",
        "uptime",
    ])
    def test_safe_commands_no_confirmation(self, detector, command):
        """Safe read-only commands should not trigger confirmation."""
        assert detector.is_explicitly_safe(command), (
            f"Command should be explicitly safe: {command}"
        )
        assert detector.get_risk_level(command) == 'safe', (
            f"Command should be safe risk level: {command}"
        )

    # ==================== File system tests ====================

    @pytest.mark.parametrize("command", [
        "mkfs.ext4 /dev/sda1",
        "mkfs -t ext4 /dev/sda1",
        "format C:",
        "fdisk /dev/sda",
        "parted /dev/sda",
    ])
    def test_filesystem_operations_trigger_confirmation(self, detector, command):
        """Filesystem operations should trigger confirmation."""
        assert detector.is_destructive(command), (
            f"Filesystem operation should be destructive: {command}"
        )

    # ==================== System command tests ====================

    @pytest.mark.parametrize("command", [
        "chmod 777 /etc/passwd",
        "kill -9 1234",
        "killall python",
        "pkill -f myapp",
        "reboot",
        "shutdown now",
        "halt",
        "init 0",
        "init 6",
    ])
    def test_system_commands_trigger_confirmation(self, detector, command):
        """System-level commands should trigger confirmation."""
        assert detector.is_destructive(command), (
            f"System command should be destructive: {command}"
        )

    # ==================== Database command tests ====================

    @pytest.mark.parametrize("command", [
        "mysql -e 'DROP DATABASE mydb'",
        "psql -c 'DROP TABLE users'",
        "sqlite3 db.sqlite 'DELETE FROM users'",
        "mongo --eval 'db.dropDatabase()'",
    ])
    def test_database_commands_trigger_confirmation(self, detector, command):
        """Database destructive commands should trigger confirmation."""
        assert detector.is_destructive(command), (
            f"Database command should be destructive: {command}"
        )


class TestRiskLevels:
    """Tests for risk level classification."""

    @pytest.fixture
    def detector(self):
        """Create a detector instance."""
        return DestructiveCommandDetector()

    def test_critical_risk_examples(self, detector):
        """Test commands that should be critical risk."""
        critical_commands = [
            "rm -rf /",
            "dd if=/dev/zero of=/dev/sda",
            "mkfs.ext4 /dev/sda",
            "sudo rm -rf /var",
            "DROP DATABASE production",
        ]
        for cmd in critical_commands:
            risk = detector.get_risk_level(cmd)
            assert risk == 'critical', f"Expected critical for: {cmd}, got: {risk}"

    def test_high_risk_examples(self, detector):
        """Test commands that should be high risk."""
        high_commands = [
            "rm -rf ./temp/",
            "dd if=file.iso of=out.img",
            "kill -9 $(pgrep python)",
            "truncate -s 0 file.log",
        ]
        for cmd in high_commands:
            risk = detector.get_risk_level(cmd)
            assert risk in ['critical', 'high'], f"Expected high+ for: {cmd}, got: {risk}"

    def test_safe_commands(self, detector):
        """Test commands that should be safe."""
        safe_commands = [
            "ls -la",
            "cat README.md",
            "grep error log.txt",
            "pwd",
        ]
        for cmd in safe_commands:
            risk = detector.get_risk_level(cmd)
            assert risk == 'safe', f"Expected safe for: {cmd}, got: {risk}"


class TestHookifyIntegration:
    """Test integration with the hookify plugin."""

    def test_hookify_rule_engine_with_rm(self, hookify_rule_engine, create_rule_file):
        """Test hookify rule engine blocks rm -rf commands."""
        # Import helper for creating hook input
        from tests.safety.conftest import create_bash_input

        # Create a rule to block rm -rf
        create_rule_file(
            name="block-rm-rf",
            event="bash",
            pattern=r"rm\s+-rf",
            action="block",
            message="Blocked: rm -rf is a destructive command"
        )

        # Reload rules after creating file
        from hookify.core.config_loader import load_rules
        rules = load_rules(event="bash")

        # Test with destructive command
        input_data = create_bash_input("rm -rf /tmp/test")
        result = hookify_rule_engine.evaluate_rules(rules, input_data)

        # Should be blocked
        assert 'hookSpecificOutput' in result or 'systemMessage' in result

    def test_hookify_rule_engine_allows_safe_commands(
        self, hookify_rule_engine, create_rule_file
    ):
        """Test hookify rule engine allows safe commands."""
        from tests.safety.conftest import create_bash_input

        # Create a rule to block rm -rf
        create_rule_file(
            name="block-rm-rf",
            event="bash",
            pattern=r"rm\s+-rf",
            action="block",
            message="Blocked: rm -rf is a destructive command"
        )

        from hookify.core.config_loader import load_rules
        rules = load_rules(event="bash")

        # Test with safe command
        input_data = create_bash_input("ls -la")
        result = hookify_rule_engine.evaluate_rules(rules, input_data)

        # Should NOT be blocked (empty result)
        assert result == {} or 'hookSpecificOutput' not in result

    def test_hookify_dd_command_detection(
        self, hookify_rule_engine, create_rule_file
    ):
        """Test hookify can detect dd commands."""
        from tests.safety.conftest import create_bash_input

        # Create a rule to block dd
        create_rule_file(
            name="block-dd",
            event="bash",
            pattern=r"dd\s+if=",
            action="block",
            message="Blocked: dd command can cause data loss"
        )

        from hookify.core.config_loader import load_rules
        rules = load_rules(event="bash")

        # Test with dd command
        input_data = create_bash_input("dd if=/dev/zero of=/dev/sda")
        result = hookify_rule_engine.evaluate_rules(rules, input_data)

        # Should be blocked
        assert 'hookSpecificOutput' in result or 'systemMessage' in result
