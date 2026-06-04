---
name: spec-implementation-notes
description: Implement a provided spec while maintaining a running implementation-notes.md file. Use when the user asks to implement a spec, plan, ticket, or requirements document and wants ongoing notes about design decisions, deviations, tradeoffs, or open questions.
---

# Spec Implementation Notes

Use this skill when implementing a user-provided `<SPEC>` or requirements document and the user wants a running `implementation-notes.md` record.

## Core Workflow

1. Read and understand the spec before changing code.
2. Create or update `implementation-notes.md` at the project root unless the user requests a different path.
3. Keep the notes current while you work, not just at the end.
4. Record reviewer-relevant context whenever the implementation interprets, narrows, extends, or departs from the spec.
5. At completion, summarize the important notes and point the user to `implementation-notes.md`.

## What to Capture

Maintain these sections in the Markdown file:

- **Design decisions**: choices made where the spec was ambiguous.
- **Deviations**: intentional departures from the spec, with rationale.
- **Tradeoffs**: alternatives considered and why the chosen approach won.
- **Open questions**: anything the user should confirm, revise, or decide later.

Only include useful information. Do not log routine implementation steps, mechanical file edits, or private chain-of-thought.

## Markdown File Requirements

The file should be a standalone, readable Markdown document. Prefer this structure:

```markdown
# Implementation Notes

Running notes on how the implementation interprets or diverges from the spec.

## Design decisions

- None yet.

## Deviations

- None yet.

## Tradeoffs

- None yet.

## Open questions

- None yet.
```

When adding the first real item to a section, remove that section's `None yet.` placeholder.

## Updating Guidance

- Update the file as soon as a decision, deviation, tradeoff, or open question appears.
- Use concise bullets that state the context, the choice, and the reason.
- If an open question is resolved during the session, either remove it or mark it as resolved with the outcome.
- If there are no deviations or open questions, keep the explicit `None yet.` placeholders so the absence is intentional.

## Completion Checklist

Before final response:

- Confirm `implementation-notes.md` exists.
- Confirm each required section is present.
- Mention any high-impact decisions, deviations, tradeoffs, or open questions in the final response.
