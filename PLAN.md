# Linear Operating Model

## Goals
- Clean intake from `#product-bugs` with fast triage.
- 2-week cycles with clear ownership.
- Minimal, meaningful labels.
- Clear separation of initiatives vs projects vs issues.

## Intake
- Channel: `#product-bugs`
- We already have a webhook that syncs every message into Linear.
- Proposed flow:
  - Post an auto-reply in Slack that @mentions Linear Agent.
  - Agent decides: create issue vs ask for more details in thread.
  - If created: set status `Triage`, apply template, apply labels, suggest project.
- Triage rotation: weekly (name list maintained in Linear doc or Slack channel topic).

## Templates
- `Bug` template fields:
  - Impact
  - Customer/Org
  - Steps to reproduce
  - Expected vs actual
  - Logs/links
- `Request` template fields:
  - Problem statement
  - Expected outcome
  - Customer/segment
  - Notes/links

## Statuses
- `Triage` -> `Todo` -> `In Progress` -> `In Review` -> `Ready to test` -> `Done` / `Canceled`
- Only `Triage` is used for new intake.
- Use labels for design context instead of custom design statuses.

## Cycles
- 2-week cycles, aligned to Monday start.
- Required fields for cycle scope: issue must have `priority`, `assignee`, and `project`.
- Priority definitions (for cycle planning):
  - `P1` (Urgent): production down, data loss, or legal/security exposure. Same-day response.
  - `P2` (High): major user-facing regression or broken core flow. Fix in current cycle.
  - `P3` (Normal): standard work. Pull into cycle only if scoped + assigned.
  - `P4` (Low): nice-to-have, defer until capacity is clear.
- Cycle planning rule: only `P1` and `P2` are allowed into an active cycle by default. `P3`/`P4` stay in backlog unless explicitly pulled.

## Labels (minimize)
- Label groups:
  - `type`: `bug`, `feature`, `tech-debt`
  - `origin`: `slack`, `customer`, `internal`
- Remove all one-off labels unless they represent a true long-term category.
- Add global product/area labels as a group:
  - `area`: `journeys`, `ai`, `inbox`, `public-api`, `mobile`, `web`, `integrations`, `appointments`, `campaigns`, `automations`, `forms`, `settings`, `postal`, `performance`, `dx`

## Projects & Initiatives
- Initiatives should be our OKRs (to be provided).
- Initiatives: only company-level outcomes (1–5 max).
- Projects: real bodies of work with clear owner + measurable goal.
- Projects must include timelines (start date + target date or explicitly “no target”).

## LLM Support
- Use Linear Agent with a prompt that tells it when to create issues, when to request details, which labels to apply, and which project to assign.
- On issue creation:
  - Generate summary
  - Normalize title
  - Extract template fields
  - Suggest priority
  - Duplicate detection
- On issue done:
  - Auto-generate resolution summary posted in Slack thread

## Linear Agent Prompt (Draft)
1) Always reply in the Slack thread.
2) If the message is a bug report, use the Bug template.
3) If the message is a request or unclear, use the Request template.
4) If critical info is missing (repro steps, org/customer, expected/actual):
   - Ask up to 3 short questions in-thread.
   - Do not create the issue yet. Create only after enough details are provided.
5) Apply labels:
   - origin: slack
   - type: bug/feature/tech-debt based on content
   - area: best matching area label
6) Guess the most likely project and set it; if unsure, leave project empty.
7) Normalize title to be concise and specific.
8) Add a short summary comment on the issue with extracted details.

---

# TODO: Cleanup Plan

1. Enable/confirm Triage
- Ensure Triage is active and set as the default status for new Slack-created issues.

2. Set 2-week cycles
- Switch cycle duration to 2 weeks.
- Align start day (prefer Monday).
- Update next cycle dates.
- Enforce cycle rule: only `P1`/`P2` default into the current cycle.
- Audit current cycle: move all `P3`/`P4` out unless explicitly planned.

3. Normalize statuses
- Keep only: `Triage`, `Todo`, `In Progress`, `In Review`, `Ready to test`, `Done`, `Canceled`.
- Move any active issues in legacy statuses into the nearest equivalent.

4. Label cleanup
- Create label groups: `type`, `origin`, `area`.
- Map existing labels to new groups:
  - `bug` -> `type: bug`
  - `feature` -> `type: feature`
  - `slack` -> `origin: slack`
- Add area labels (final list):
  - `journeys`, `ai`, `inbox`, `public-api`, `mobile`, `web`
  - `integrations`, `appointments`, `campaigns`, `automations`, `forms`, `settings`, `postal`, `performance`, `dx`
- `pending-release`, `released` -> remove or move to project fields/status
- Archive/delete all other labels.

5. Project hygiene
- For active projects, ensure:
  - Owner assigned
  - Clear target date or "no target"
  - Project labels assigned for area
- Archive stale or duplicate projects.

6. Initiative hygiene
- Keep only true company goals.
- Remove "initiatives as categories."

7. Views & triage dashboards
- Create standard views:
  - Triage: Bugs (status = Triage, type = bug)
  - Triage: Feature requests (status = Triage, type = feature)
  - Triage: Tech debt (status = Triage, type = tech-debt)
  - Current cycle: P1/P2 only
  - Backlog: P3/P4 only

8. Slack + LLM setup
- Auto-reply to every message in `#product-bugs` with @Linear Agent.
- Add Linear Slack Agent guidance:
  - route to `hellomateo`
  - status `Triage`
  - template = `Bug`
  - labels = `origin: slack`, `type: bug` (LLM can override)
  - only create issue when enough info is provided
  - guess and set project when possible
