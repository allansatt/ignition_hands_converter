# Agent instructions

- **Be concise** when answering questions. Prefer short, direct answers over long explanations unless depth is clearly needed.
- **Always give examples** when discussing issues (bugs, errors, design tradeoffs, or how to do something). One concrete example per point is enough.

Example of the style we want: instead of only saying "the hook exits when the state file is missing," add something like "e.g. after `rm .check-remaining-tasks.state`, the next run will exit 0 and not prompt to continue."

# Package Management
- use uv for packagem management and venv management