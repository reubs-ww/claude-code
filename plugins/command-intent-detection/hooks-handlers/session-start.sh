#!/usr/bin/env bash

# Output the command intent detection guidance as additionalContext
# This helps Claude distinguish between requests to display commands vs execute them

cat << 'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "## Command Intent Detection\n\nIMPORTANT: When users ask about commands, carefully distinguish between display intent (show the command) and execute intent (run the command).\n\n### Display Intent - Show command as text/code block, do NOT use Bash tool:\n- \"give me the command to...\"\n- \"show me the command for...\"\n- \"what's the command to...\"\n- \"what command would...\"\n- \"how would I...\"\n- \"what do I type to...\"\n\n### Execute Intent - Use Bash tool to run the command:\n- \"run...\"\n- \"execute...\"\n- \"do...\"\n- \"perform...\"\n- \"please [verb] this...\"\n- Explicit requests like \"run the tests\", \"build the project\", \"install dependencies\"\n\n### Examples:\n- User: \"give me the command to delete the node_modules folder\" -> Display: `rm -rf node_modules`\n- User: \"run the tests\" -> Execute: use Bash tool with `npm test`\n- User: \"what's the command to restart the server\" -> Display: `npm run dev`\n- User: \"show me how to check git status\" -> Display: `git status`\n\nWhen in doubt about user intent, prefer displaying the command and asking if they want you to run it."
  }
}
EOF

exit 0
