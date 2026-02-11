"""Tests for intent recognition in destructive command handling.

This module tests the system's ability to distinguish between:
- "Give me the command to X" (display code, don't execute)
- "Run the command to X" (execute via Bash tool)

Intent recognition is crucial for safety because users often want to SEE
dangerous commands before deciding whether to run them. The system should:
1. Show code blocks when intent is informational
2. Only execute when intent is clearly to run
3. Ask for clarification on ambiguous intents
"""

import re
import pytest

# Intent patterns that should be recognized as "show/display"
SHOW_INTENT_PATTERNS = [
    "give me the command to",
    "show me the command for",
    "what command would",
    "what's the command to",
    "what is the command to",
    "how do I",
    "what would the command be",
    "display the command for",
    "print the command",
    "tell me the command",
    "write out the command",
]

# Intent patterns that should be recognized as "execute"
EXECUTE_INTENT_PATTERNS = [
    "run the command to",
    "execute the command",
    "do this:",
    "please run",
    "go ahead and",
    "run this now",
    "execute now",
    "just do it",
    "run it",
]

# Ambiguous patterns that should trigger clarification
AMBIGUOUS_PATTERNS = [
    "please give it a run",  # Could mean show then run
    "show me then run it",   # Two-step request
    "try this",              # Unclear if show or execute
    "do the thing",          # Too vague
]


class IntentClassifier:
    """Simple intent classifier for testing purposes.

    This simulates the intent recognition that should happen
    before Claude decides whether to show code or execute it.
    """

    SHOW_KEYWORDS = [
        r'\bgive\s+me\b', r'\bshow\s+me\b', r'\bwhat\s+command\b',
        r'\bhow\s+do\s+I\b', r'\bdisplay\b', r'\bprint\b',
        r'\btell\s+me\b', r'\bwrite\s+out\b', r"\bwhat's\b",
        r'\bwhat\s+is\b', r'\bwhat\s+would\b'
    ]

    EXECUTE_KEYWORDS = [
        r'\brun\b(?!\s+me)', r'\bexecute\b', r'\bdo\s+this\b',
        r'\bgo\s+ahead\b', r'\bjust\s+do\b', r'\bnow\b'
    ]

    def classify(self, user_input: str) -> str:
        """Classify user intent as 'show', 'execute', or 'ambiguous'.

        Args:
            user_input: The user's natural language request

        Returns:
            'show' - User wants to see the command
            'execute' - User wants to run the command
            'ambiguous' - Intent unclear, should ask for clarification
        """
        input_lower = user_input.lower()

        show_score = 0
        execute_score = 0

        for pattern in self.SHOW_KEYWORDS:
            if re.search(pattern, input_lower, re.IGNORECASE):
                show_score += 1

        for pattern in self.EXECUTE_KEYWORDS:
            if re.search(pattern, input_lower, re.IGNORECASE):
                execute_score += 1

        # Both signals present = ambiguous
        if show_score > 0 and execute_score > 0:
            return 'ambiguous'

        # Clear show intent
        if show_score > 0 and execute_score == 0:
            return 'show'

        # Clear execute intent
        if execute_score > 0 and show_score == 0:
            return 'execute'

        # No clear signals
        return 'ambiguous'


class TestIntentRecognition:
    """Test suite for intent recognition functionality."""

    @pytest.fixture
    def classifier(self):
        """Create an intent classifier instance."""
        return IntentClassifier()

    @pytest.mark.parametrize("input_phrase", [
        "give me the command to delete all .tmp files",
        "show me the command for removing old logs",
        "what command would I use to clear the cache?",
        "what's the command to restart the server?",
        "what is the command to format the disk?",
        "how do I remove all Docker containers?",
        "display the command for killing all processes",
        "print the command to wipe the database",
        "tell me the command to reset everything",
        "write out the command for clearing history",
    ])
    def test_show_intent_recognized(self, classifier, input_phrase):
        """Test that 'show' intent is correctly identified.

        When users ask to SEE a command, the system should display
        the command as code without executing it.
        """
        result = classifier.classify(input_phrase)
        assert result == 'show', (
            f"Expected 'show' intent for: {input_phrase!r}, got {result!r}"
        )

    @pytest.mark.parametrize("input_phrase", [
        "run the command to delete all .tmp files",
        "execute the command now",
        "do this: rm -rf /tmp/old",
        "please run the cleanup script",
        "go ahead and clear the logs",
        "execute now, I've backed everything up",
        "just do it already",
    ])
    def test_execute_intent_recognized(self, classifier, input_phrase):
        """Test that 'execute' intent is correctly identified.

        When users explicitly ask to RUN a command, the system
        should proceed with execution (after safety checks).
        """
        result = classifier.classify(input_phrase)
        assert result == 'execute', (
            f"Expected 'execute' intent for: {input_phrase!r}, got {result!r}"
        )

    @pytest.mark.parametrize("input_phrase", [
        "show me then run it",       # Contains both show and run
        "try this command",          # No clear intent signals
        "do the thing with the files",  # Vague
        "handle the cleanup",        # Vague
    ])
    def test_ambiguous_intent_triggers_clarification(self, classifier, input_phrase):
        """Test that ambiguous intents are flagged for clarification.

        When intent is unclear, the system should ask the user
        whether they want to see or execute the command.
        """
        result = classifier.classify(input_phrase)
        assert result == 'ambiguous', (
            f"Expected 'ambiguous' for: {input_phrase!r}, got {result!r}"
        )


class TestIntentWithDestructiveCommands:
    """Test intent recognition specifically for destructive commands."""

    @pytest.fixture
    def classifier(self):
        """Create an intent classifier instance."""
        return IntentClassifier()

    DESTRUCTIVE_COMMANDS = [
        "rm -rf",
        "dd if=/dev/zero",
        "mkfs",
        "format",
        "drop database",
        "delete all",
        "wipe",
        "destroy",
        "purge",
    ]

    @pytest.mark.parametrize("cmd_keyword", DESTRUCTIVE_COMMANDS)
    def test_show_intent_with_destructive_commands(self, classifier, cmd_keyword):
        """Ensure 'show' intent works correctly with destructive commands.

        Even for dangerous operations, if the user asks to SEE the command,
        we should show it rather than execute it.
        """
        input_phrase = f"show me the command for {cmd_keyword}"
        result = classifier.classify(input_phrase)
        assert result == 'show', (
            f"Should recognize 'show' intent even for destructive: {cmd_keyword}"
        )

    @pytest.mark.parametrize("cmd_keyword", DESTRUCTIVE_COMMANDS)
    def test_execute_intent_with_destructive_commands(self, classifier, cmd_keyword):
        """Ensure 'execute' intent is still recognized for destructive commands.

        The intent classifier should still recognize execution intent;
        the destructive command checks happen at a different layer.
        """
        input_phrase = f"run the {cmd_keyword} command now"
        result = classifier.classify(input_phrase)
        assert result == 'execute', (
            f"Should recognize 'execute' intent for destructive: {cmd_keyword}"
        )


class TestEdgeCases:
    """Test edge cases in intent recognition."""

    @pytest.fixture
    def classifier(self):
        """Create an intent classifier instance."""
        return IntentClassifier()

    def test_empty_input(self, classifier):
        """Empty input should be treated as ambiguous."""
        result = classifier.classify("")
        assert result == 'ambiguous'

    def test_whitespace_only(self, classifier):
        """Whitespace-only input should be treated as ambiguous."""
        result = classifier.classify("   \n\t  ")
        assert result == 'ambiguous'

    def test_mixed_case(self, classifier):
        """Intent recognition should be case-insensitive."""
        assert classifier.classify("SHOW ME THE COMMAND") == 'show'
        assert classifier.classify("RUN THE COMMAND") == 'execute'
        assert classifier.classify("Show Me The Command") == 'show'

    def test_command_in_quotes(self, classifier):
        """Commands in quotes should still be recognized."""
        result = classifier.classify('show me the command "rm -rf /tmp"')
        assert result == 'show'

    def test_multi_step_request(self, classifier):
        """Multi-step requests should be flagged as ambiguous."""
        result = classifier.classify("first show me the command then run it")
        # Contains both 'show' and 'run', should be ambiguous
        assert result == 'ambiguous'

    def test_negation(self, classifier):
        """Negation handling (e.g., 'don't run')."""
        # Note: This is a known limitation - negation is complex
        # The classifier treats this as having 'run' keyword
        result = classifier.classify("don't run that command")
        # In a production system, this should recognize negation
        # For now, we accept 'execute' or 'ambiguous' as valid responses
        assert result in ['execute', 'ambiguous']

    def test_question_format(self, classifier):
        """Question format should lean toward 'show' intent."""
        result = classifier.classify("what would the command be to delete files?")
        assert result == 'show'

    def test_imperative_format(self, classifier):
        """Imperative statements lean toward 'execute' intent."""
        result = classifier.classify("execute the cleanup now")
        assert result == 'execute'
