#!/usr/bin/env bash

# Output file reference validation guidance as additionalContext
# This ensures Claude explicitly states which file is being targeted
# before performing destructive operations

cat << 'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "## File Reference Resolution\n\nWhen users refer to files contextually using phrases like 'the file', 'that file', 'it', 'the one I mentioned', or similar demonstrative/pronoun references, you MUST follow these safety guidelines:\n\n### Before Destructive Operations\nFor any destructive command (rm, rmdir, del, unlink, shred, trash, or file removal in any form):\n\n1. **Identify** the most recently mentioned file in the conversation\n2. **State explicitly** which file you're targeting: 'I'll target /path/to/file.ext'\n3. **Wait for confirmation** if the file was inferred from earlier context\n4. **Warn** if multiple files could match the reference\n\n### Key Patterns to Watch For\n- 'delete the file I mentioned'\n- 'remove that file'\n- 'rm it'\n- 'delete the one we discussed'\n- 'get rid of that'\n- Any destructive command + pronoun/demonstrative reference\n\n### Safety Protocol\nNever assume which file is meant if:\n- Multiple files were discussed recently\n- The file reference is ambiguous\n- Significant time/messages have passed since the file was mentioned\n- The path seems to differ from what was previously discussed\n\nWhen in doubt, ask the user to clarify which specific file path they want to operate on."
  }
}
EOF

exit 0
