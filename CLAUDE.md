# Project Instructions for Claude

## Project: community-orgs-portal

This project uses an AI-assisted development system for design documentation, conventions, and domain knowledge.

## Knowledge System Location

`~/ai-dev-system/`

## Before Responding to Implementation Questions

1. **Read the grounding protocol**: `~/ai-dev-system/core/prompts/grounding-protocol.md`
2. **Check project design docs**: `~/ai-dev-system/projects/community-orgs-portal/design/`
3. **Follow conventions**: `~/ai-dev-system/core/conventions/`
4. **Reference domain knowledge**: `~/ai-dev-system/domains/community-environmental-management/`

## Source Priority (highest to lowest)

1. Project design documents and ADRs in `~/ai-dev-system/projects/community-orgs-portal/design/`
2. Code conventions in `~/ai-dev-system/core/conventions/`
3. Library documentation (via GitHub MCP or Fetch MCP)
4. Domain knowledge in `~/ai-dev-system/domains/community-environmental-management/`
5. General knowledge (flag as unverified)

## When Providing Code

- Follow patterns in `~/ai-dev-system/core/conventions/component-patterns.md`
- Follow database conventions in `~/ai-dev-system/core/conventions/database-conventions.md`
- Follow API conventions in `~/ai-dev-system/core/conventions/api-conventions.md`
- Cite sources for technical recommendations
- Flag uncertainty rather than guessing

## Project Context

| Attribute | Value |
|-----------|-------|
| **Project name** | community-orgs-portal |
| **Domain** | Community Environmental Management |
| **Design docs** | `~/ai-dev-system/projects/community-orgs-portal/design/` |
| **Current iteration** | v0.1 |
| **Related project** | bendev-web (same repo) |

## Technology Stack

- **Frontend**: SvelteKit + Skeleton UI (Svelte 5 runes)
- **Backend**: Supabase (PostgreSQL + PostGIS)
- **Spatial**: PostGIS
- **Mapping**: [Leaflet/OpenLayers]

## Key Commands

```bash
# Development
npm run dev

# Build
npm run build

# Check types
npm run check
```

## Important Files

- `src/routes/` — SvelteKit routes
- `src/lib/` — Shared components and utilities
- `supabase/migrations/` — Database migrations (if present)

## Related Project

This project shares a repository with `bendev-web`. 
Design docs for that project: `~/ai-dev-system/projects/bendev-web/design/`
