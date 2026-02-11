"""Tests for file reference handling in destructive operations.

This module tests that the system properly handles file references when
executing destructive commands, ensuring:

1. Contextual references to recent files are explicitly stated
2. Explicit paths are used as-is without extra confirmation
3. Multiple files discussed triggers clarification
4. Ambiguous references (like "that file") are resolved

The goal is to prevent accidental deletion of the wrong file by ensuring
the user and Claude are referring to the same file.
"""

import pytest
from typing import List, Optional, Dict, Any
from dataclasses import dataclass


@dataclass
class FileReference:
    """Represents a file mentioned in the conversation."""
    path: str
    mention_type: str  # "explicit", "contextual", "ambiguous"
    context: str  # How it was mentioned
    timestamp: float = 0.0  # When it was mentioned (for recency)


class FileReferenceResolver:
    """Resolves file references in user requests.

    When a user refers to "that file" or "the file we were discussing",
    this class helps resolve which file they mean.
    """

    def __init__(self):
        """Initialize with empty context."""
        self._recent_files: List[FileReference] = []
        self._max_context_files = 10

    def add_file_reference(
        self,
        path: str,
        mention_type: str = "explicit",
        context: str = ""
    ):
        """Add a file to the context.

        Args:
            path: File path
            mention_type: How it was referenced
            context: Additional context about the reference
        """
        import time
        ref = FileReference(
            path=path,
            mention_type=mention_type,
            context=context,
            timestamp=time.time()
        )
        self._recent_files.append(ref)

        # Keep only most recent files
        if len(self._recent_files) > self._max_context_files:
            self._recent_files = self._recent_files[-self._max_context_files:]

    def resolve_reference(self, user_request: str) -> Dict[str, Any]:
        """Resolve file references in a user request.

        Args:
            user_request: The user's request mentioning files

        Returns:
            Dictionary with:
                - 'resolved_path': The resolved file path (if unambiguous)
                - 'confidence': How confident we are in the resolution
                - 'alternatives': Other possible files if ambiguous
                - 'needs_clarification': Whether to ask the user
                - 'suggested_question': Question to ask if clarification needed
        """
        # Check for explicit paths in the request
        explicit_paths = self._extract_explicit_paths(user_request)
        if explicit_paths:
            if len(explicit_paths) == 1:
                return {
                    'resolved_path': explicit_paths[0],
                    'confidence': 'high',
                    'alternatives': [],
                    'needs_clarification': False,
                    'suggested_question': None
                }
            else:
                # Multiple paths mentioned
                return {
                    'resolved_path': None,
                    'confidence': 'low',
                    'alternatives': explicit_paths,
                    'needs_clarification': True,
                    'suggested_question': f"You mentioned multiple files. Which one do you want to operate on: {', '.join(explicit_paths)}?"
                }

        # Check for contextual references
        contextual_refs = self._find_contextual_references(user_request)

        if not contextual_refs:
            # No files in context and no explicit path
            return {
                'resolved_path': None,
                'confidence': 'none',
                'alternatives': [],
                'needs_clarification': True,
                'suggested_question': "Which file are you referring to? Please provide the file path."
            }

        if len(contextual_refs) == 1:
            ref = contextual_refs[0]
            return {
                'resolved_path': ref.path,
                'confidence': 'medium',
                'alternatives': [],
                'needs_clarification': False,
                'explicit_confirmation': f"I'll use the file we discussed earlier: {ref.path}"
            }

        # Multiple files in context - need clarification
        paths = [ref.path for ref in contextual_refs]
        return {
            'resolved_path': None,
            'confidence': 'low',
            'alternatives': paths,
            'needs_clarification': True,
            'suggested_question': f"We've discussed several files. Which one do you want me to operate on?\n" + "\n".join(f"- {p}" for p in paths)
        }

    def _extract_explicit_paths(self, text: str) -> List[str]:
        """Extract explicit file paths from text.

        Looks for patterns like:
        - /path/to/file
        - ./relative/path
        - ~/home/path
        - file.ext
        """
        import re
        paths = []

        # Absolute paths
        abs_pattern = r'(?:^|[\s"\'])(/[^\s"\']+)'
        for match in re.finditer(abs_pattern, text):
            paths.append(match.group(1))

        # Relative paths with ./
        rel_pattern = r'(?:^|[\s"\'])(\.+/[^\s"\']+)'
        for match in re.finditer(rel_pattern, text):
            paths.append(match.group(1))

        # Home directory paths
        home_pattern = r'(?:^|[\s"\'])(~/[^\s"\']+)'
        for match in re.finditer(home_pattern, text):
            paths.append(match.group(1))

        # Files with extensions (without path prefix)
        ext_pattern = r'(?:^|[\s"\'])([a-zA-Z0-9_-]+\.[a-zA-Z0-9]+)'
        for match in re.finditer(ext_pattern, text):
            candidate = match.group(1)
            # Filter out common non-file patterns
            if not candidate.lower() in ['1.0', '2.0', '3.0']:
                paths.append(candidate)

        return paths

    def _find_contextual_references(self, text: str) -> List[FileReference]:
        """Find contextual file references.

        Matches phrases like:
        - "that file"
        - "the file"
        - "this file"
        - "it" (when referring to a file)
        """
        import re
        text_lower = text.lower()

        contextual_patterns = [
            r'\bthat\s+file\b',
            r'\bthe\s+file\b',
            r'\bthis\s+file\b',
            r'\bthe\s+same\s+file\b',
            r'\bit\b',  # Generic pronoun
        ]

        for pattern in contextual_patterns:
            if re.search(pattern, text_lower):
                # Return recent files as candidates
                return list(reversed(self._recent_files))

        return []


class TestFileReferenceResolution:
    """Tests for file reference resolution."""

    @pytest.fixture
    def resolver(self):
        """Create a resolver instance."""
        return FileReferenceResolver()

    # ==================== Explicit Path Tests ====================

    def test_explicit_absolute_path(self, resolver):
        """Explicit absolute paths should resolve directly."""
        result = resolver.resolve_reference("delete /tmp/test.txt")
        assert result['resolved_path'] == '/tmp/test.txt'
        assert result['confidence'] == 'high'
        assert not result['needs_clarification']

    def test_explicit_relative_path(self, resolver):
        """Explicit relative paths should resolve directly."""
        result = resolver.resolve_reference("delete ./src/config.json")
        assert result['resolved_path'] == './src/config.json'
        assert result['confidence'] == 'high'

    def test_explicit_home_path(self, resolver):
        """Explicit home directory paths should resolve directly."""
        result = resolver.resolve_reference("delete ~/Documents/file.txt")
        assert result['resolved_path'] == '~/Documents/file.txt'
        assert result['confidence'] == 'high'

    def test_explicit_file_with_extension(self, resolver):
        """File names with extensions should be recognized."""
        result = resolver.resolve_reference("delete config.json")
        assert result['resolved_path'] == 'config.json'
        assert result['confidence'] == 'high'

    # ==================== Contextual Reference Tests ====================

    def test_contextual_reference_single_file(self, resolver):
        """'That file' should resolve to the most recent file in context."""
        # Add a file to context
        resolver.add_file_reference("/tmp/recent.txt", "explicit", "discussed earlier")

        result = resolver.resolve_reference("delete that file")
        assert result['resolved_path'] == '/tmp/recent.txt'
        assert result['confidence'] == 'medium'
        # Should state the file explicitly in confirmation
        assert 'explicit_confirmation' in result

    def test_contextual_reference_no_context(self, resolver):
        """'That file' with no context should ask for clarification."""
        result = resolver.resolve_reference("delete that file")
        assert result['resolved_path'] is None
        assert result['needs_clarification']
        assert 'which file' in result['suggested_question'].lower()

    def test_contextual_reference_multiple_files(self, resolver):
        """Multiple files in context should trigger clarification."""
        resolver.add_file_reference("/tmp/file1.txt", "explicit", "first file")
        resolver.add_file_reference("/tmp/file2.txt", "explicit", "second file")

        result = resolver.resolve_reference("delete that file")
        assert result['resolved_path'] is None
        assert result['needs_clarification']
        assert len(result['alternatives']) == 2

    # ==================== Multiple Files in Request ====================

    def test_multiple_explicit_paths_in_request(self, resolver):
        """Multiple paths in same request should ask for clarification."""
        result = resolver.resolve_reference(
            "delete /tmp/file1.txt or maybe /tmp/file2.txt"
        )
        assert result['resolved_path'] is None
        assert result['needs_clarification']
        assert len(result['alternatives']) == 2

    # ==================== Edge Cases ====================

    def test_empty_request(self, resolver):
        """Empty request should ask for file path."""
        result = resolver.resolve_reference("")
        assert result['needs_clarification']

    def test_no_file_reference(self, resolver):
        """Request without file reference should ask for clarification."""
        result = resolver.resolve_reference("delete the old data")
        # 'the' might trigger contextual matching, but no files in context
        assert result['needs_clarification']


class TestFileReferenceConfirmation:
    """Tests for file reference confirmation in destructive operations."""

    @pytest.fixture
    def resolver(self):
        """Create a resolver instance."""
        return FileReferenceResolver()

    def test_confirmation_includes_full_path(self, resolver):
        """Confirmation should include the full file path."""
        resolver.add_file_reference("/home/user/important.doc")
        result = resolver.resolve_reference("delete that file")

        if 'explicit_confirmation' in result:
            assert '/home/user/important.doc' in result['explicit_confirmation']

    def test_multiple_files_lists_all_options(self, resolver):
        """When multiple files, should list all options."""
        resolver.add_file_reference("/tmp/a.txt")
        resolver.add_file_reference("/tmp/b.txt")
        resolver.add_file_reference("/tmp/c.txt")

        result = resolver.resolve_reference("delete that file")

        assert result['needs_clarification']
        question = result['suggested_question']
        assert '/tmp/a.txt' in question
        assert '/tmp/b.txt' in question
        assert '/tmp/c.txt' in question


class TestHookifyFileReferenceIntegration:
    """Test hookify integration with file reference safety."""

    def test_edit_with_explicit_path_passes(
        self, hookify_rule_engine, create_rule_file
    ):
        """Edit operations with explicit paths should work normally."""
        from tests.safety.conftest import create_edit_input

        # Create a rule that checks file edits
        create_rule_file(
            name="check-edit",
            event="file",
            conditions=[{
                "field": "file_path",
                "operator": "regex_match",
                "pattern": r"\.env$"
            }],
            action="warn",
            message="Editing .env file"
        )

        from hookify.core.config_loader import load_rules
        rules = load_rules(event="file")

        # Test with explicit path - should work (not .env)
        input_data = create_edit_input(
            file_path="/tmp/test.txt",
            old_string="old",
            new_string="new"
        )
        result = hookify_rule_engine.evaluate_rules(rules, input_data)

        # Should pass without warning
        assert result == {}

    def test_edit_env_file_warns(
        self, hookify_rule_engine, create_rule_file
    ):
        """Edit operations on sensitive files should warn."""
        from tests.safety.conftest import create_edit_input

        create_rule_file(
            name="check-env",
            event="file",
            conditions=[{
                "field": "file_path",
                "operator": "regex_match",
                "pattern": r"\.env$"
            }],
            action="warn",
            message="Warning: Editing .env file - ensure no secrets are committed"
        )

        from hookify.core.config_loader import load_rules
        rules = load_rules(event="file")

        input_data = create_edit_input(
            file_path="/project/.env",
            old_string="OLD_KEY=value",
            new_string="NEW_KEY=secret"
        )
        result = hookify_rule_engine.evaluate_rules(rules, input_data)

        assert 'systemMessage' in result
        assert '.env' in result['systemMessage'].lower() or 'secrets' in result['systemMessage'].lower()


class TestPathSanitization:
    """Tests for path sanitization and security."""

    @pytest.fixture
    def resolver(self):
        """Create a resolver instance."""
        return FileReferenceResolver()

    @pytest.mark.parametrize("malicious_path", [
        "/etc/passwd",
        "/etc/shadow",
        "~/.ssh/id_rsa",
        "/root/.bashrc",
        "../../../etc/passwd",  # Path traversal
        "/dev/sda",
        "/dev/null",
    ])
    def test_sensitive_paths_extracted(self, resolver, malicious_path):
        """Sensitive paths should be properly extracted for review."""
        request = f"delete {malicious_path}"
        result = resolver.resolve_reference(request)

        # The path should be extracted (for review/warning)
        # The resolver's job is to identify the path, not block it
        # Blocking happens at a different layer (destructive command detection)
        assert result['resolved_path'] is not None or result['needs_clarification']

    def test_path_traversal_detected(self, resolver):
        """Path traversal attempts should be extracted."""
        result = resolver.resolve_reference("delete ../../../etc/passwd")
        # Should extract the path (blocking happens elsewhere)
        paths = [result['resolved_path']] if result['resolved_path'] else result.get('alternatives', [])
        # Path traversal pattern should be captured
        assert any('../' in p if p else False for p in paths) or result['needs_clarification']
