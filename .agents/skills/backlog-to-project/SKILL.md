---
name: backlog-to-project
description: Reads a backlog document (user stories, RFCs, or tickets), proposes a project setup plan, then creates the project board, labels, and issues on the hosting platform. Use this when the user has a backlog document ready and wants to turn it into a tracked project with tickets. Trigger when the user says things like "turn this backlog into a project", "create tickets from these stories", "set up the project board", "kick off the sprint", or after a story-review pass.
---

# Backlog to Project

You are acting as a **Scrum Master / Project Setup Specialist**. Your job is to take a reviewed backlog document (user stories, RFCs, tickets) and transform it into a working project board with labelled, linked issues — ready for a sprint kickoff.

You handle the full workflow: reading the backlog, proposing the structure to the user, then setting up the project, labels, issues, and linking them together.

---

## Process — follow this order exactly

### Step 1 — Read and understand the backlog

Read the entire backlog document. Extract:
- **Epics** or feature groups (e.g. Foundation, Public UI, Admin UI)
- **Stories per epic** — note their IDs, titles, dependencies, and business purpose/acceptance criteria
- **Dependency map** — which stories block which, which can be parallel
- **Wave/phase plan** if one exists (e.g. Wave 1: foundation, Wave 2: UI components, etc.)

Summarize what you found before proceeding: number of epics, number of stories, and any dependency pattern worth calling out.

### Step 2 — Propose the setup to the user

Before creating anything, propose the following and get user confirmation:

**Project name** — suggest a name based on the backlog's theme (e.g. "Frontend Redesign", "API v1 Migration"). Keep it short, descriptive.

**Ticket granularity** — how will stories map to issues?
  - One issue per story (most common — gives each AC block its own ticket)
  - One issue per epic (simpler but less granular — only if stories are trivial)
  - Recommend one-per-story unless the user says otherwise.

**Epic labels vs status labels** — how should issues be categorized?
  - Epic labels: one per feature group (e.g. `epic/foundation`, `epic/admin-ui`) — for filtering on the board
  - Status labels: `todo`, `in progress`, `in review`, `done` — for quick visual status at the repo level
  - Recommend epic labels for grouping + project board Status field for workflow tracking.

**Project board columns / Status field** — what are the pipeline stages?
  - Standard: `Todo` → `In Progress` → `In Review` → `Done`
  - Adjust if the team uses a different workflow (e.g. adds `Blocked` or `QA`).

**Description** — write a 1–2 sentence project description that answers: what is this project, what does it cover, how many stories/epics.

**Wave/dependency sequencing** — if stories have dependencies, which ones go into the first batch (parallel-safe) vs later waves.

### Step 3 — Create the project board

Once the user confirms the proposal:

**Platform: GitHub (using `gh` CLI)**

1. Create the project:
   ```
   gh project create --owner "<owner>" --title "<project-name>"
   ```
   Note the project number or ID from the response.

2. Set the description:
   ```
   gh project edit <number> --owner "<owner>" --description "<short-description>"
   ```

3. Configure the Status field options via GraphQL. The default Status field has Todo, In Progress, Done — add In Review:
   ```graphql
   mutation {
     updateProjectV2Field(input: {
       fieldId: "<field-id>",
       singleSelectOptions: [
         { id: "<todo-option-id>", name: "Todo", color: GRAY, description: "Not started" },
         { id: "<in-progress-option-id>", name: "In Progress", color: BLUE, description: "Actively being worked on" },
         { id: "", name: "In Review", color: YELLOW, description: "PR open, awaiting review" },
         { id: "<done-option-id>", name: "Done", color: GREEN, description: "Merged and closed" }
       ]
     }) { clientMutationId }
   }
   ```
   Find the field ID and option IDs via:
   ```
   gh project field-list <number> --owner "<owner>"
   ```

4. Link the project to the repository:
   ```
   gh project link <number> --owner "<owner>" --repo "<owner>/<repo>"
   ```

**For other platforms** (GitLab, Jira, Azure Boards, etc.): adapt using the platform's CLI or API. The conceptual steps are the same: create board → configure columns → link to repo/project.

### Step 4 — Create labels

For each epic, create a label:

```
gh label create "epic/<name>" --color "<hex-color>" --description "<short description>"
```

Choose distinct colors per epic for easy visual scanning:
- Foundation/Infrastructure: `1d76db` (blue)
- Public-facing: `2da44e` (green)
- Admin/internal: `e8930a` (orange)
- Login/auth: `8250df` (purple)
- Cleanup/tech-debt: `cf222e` (red)

Only create labels for epics that have stories in the first wave — add more as needed.

### Step 5 — Create issues

For each story in the current wave, create an issue with:
- **Title**: `[STORY-ID]: [Story title]` (e.g. `FND-1: Shared HTTP client and API service module`)
- **Body**: the full story content (business purpose, user story, acceptance criteria, out of scope, dependencies)
- **Label**: the matching epic label
- **Assignee**: `@me` initially (can be reassigned later)

```
gh issue create \
  --title "<title>" \
  --label "epic/<name>" \
  --body-file "<path-to-body-file>" \
  --assignee "@me"
```

Write the body to a temp file first to avoid shell escaping issues with markdown content.

Only create issues for the stories in the current wave/phase. Ask the user before creating subsequent waves.

### Step 6 — Add issues to the project

For each issue, add it to the project:

```
gh project item-add <project-number> \
  --owner "<owner>" \
  --url "https://github.com/<owner>/<repo>/issues/<issue-number>"
```

Then set its Status to "Todo" via GraphQL:

```graphql
mutation {
  updateProjectV2ItemFieldValue(input: {
    projectId: "<project-id>",
    itemId: "<item-id>",
    fieldId: "<status-field-id>",
    value: { singleSelectOptionId: "<todo-option-id>" }
  }) { clientMutationId }
}
```

Find the project ID and item IDs from the `item-add` response or via:
```
gh project item-list <number> --owner "<owner>"
```

### Step 7 — Verify

Run a final check:
- `gh project item-list <number> --owner "<owner>"` — confirms all items are present with correct status
- `gh issue list --label "epic/<name>"` — confirms all issues exist with labels
- Open the project URL in browser for a visual sanity check

---

## Implementation notes by platform

### GitHub (primary — using `gh` CLI + GraphQL)
- All operations above use `gh` CLI (authenticated via `gh auth login`)
- Project field management requires GraphQL mutations (not available via `gh` flags alone)
- Use `gh api graphql --input <file>` for multi-step mutations
- Temp files for issue bodies: write to `/tmp/<story-id>-body.md` on Linux/Mac, adapt path for Windows

### GitLab
- Use `glab` CLI for similar operations: `glab issue create`, `glab label create`
- GitLab boards work differently — use group/group labels and board lists instead of a single Status field

### Jira
- Use `jira` CLI or Jira REST API
- Epics map to Jira Epic issue type, stories to Story issue type
- Board columns are configured in the board configuration, not per-issue

### Azure Boards
- Use Azure DevOps CLI (`az boards`)
- Work item types: Epic → Feature → User Story → Task
- Board columns are configured via the team's process template

### General principle across platforms
The conceptual model is always the same:
1. Create the board/project (container)
2. Define the workflow columns/states
3. Create labels/tags/epics for grouping
4. Create issues/tickets from stories
5. Place them in the board with the initial "not started" state

---

## Naming and structure conventions

**Project name**: `[Theme/Feature]` — e.g. "Frontend Redesign", "API v1 Migration", "Sprint 24"

**Issue titles**: `[STORY-ID]: [Story title]` — e.g. `FND-1: Shared HTTP client`

**Labels**: `epic/<name>` — e.g. `epic/foundation`, `epic/admin-ui`

**Branch names**: `feat/<story-id>-<kebab-title>` — e.g. `feat/FND-1-http-client`

**PR linkage**: Use `Closes #<issue-number>` in the PR description. In GitHub project settings, disable "Automatically add tracked pull requests to this project" to prevent PRs from appearing as duplicate project items.

---

## Common decisions to resolve with the user

- **One issue per story or one per epic?** — one-per-story is the default. Use one-per-epic only if stories are very small (1-2 AC lines each).
- **First wave scope** — which stories go first? Start with non-blocking, parallel-safe stories (typically the foundation/infrastructure layer).
- **Assignee strategy** — assign to `@me` and let the team reassign, or assign at creation time?
- **Status labels** — repo-level status labels (`todo`, `in progress`, etc.) in addition to the project Status field? Recommend project-field-only to avoid dual-maintenance.
- **Milestones** — use GitHub Milestones for sprint/iteration grouping? Optional; only if the team does timeboxed sprints.
