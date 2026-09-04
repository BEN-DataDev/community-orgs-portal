community-orgs-portal/
├── src/
│   ├── lib/
│   │   ├── components/
│   │   │   ├── forms/
│   │   │   │   ├── OrganisationForm.svelte
│   │   │   │   ├── LegalDetailsForm.svelte
│   │   │   │   ├── ContactForm.svelte
│   │   │   │   ├── RoleBuilder.svelte
│   │   │   │   └── ... (other form components)
│   │   │   ├── tables/
│   │   │   │   ├── OrganisationTable.svelte
│   │   │   │   ├── DataTable.svelte
│   │   │   │   └── TableFilters.svelte
│   │   │   ├── navigation/
│   │   │   │   ├── Sidebar.svelte
│   │   │   │   ├── Breadcrumbs.svelte
│   │   │   │   └── TopNav.svelte
│   │   │   └── common/
│   │   │       ├── Button.svelte
│   │   │       ├── Modal.svelte
│   │   │       └── Card.svelte
│   │   ├── stores/
│   │   │   ├── organizationStore.ts
│   │   │   ├── userStore.ts
│   │   │   └── filterStore.ts
│   │   ├── services/
│   │   │   ├── api.ts
│   │   │   ├── auth.ts
│   │   │   └── database.ts
│   │   ├── types/
│   │   │   └── index.ts
│   │   └── utils/
│   │       ├── validation.ts
│   │       └── formatters.ts
│   ├── routes/
│   │   ├── +layout.svelte
│   │   ├── +page.svelte
│   │   ├── organizations/
│   │   │   ├── +page.svelte
│   │   │   ├── +page.server.ts
│   │   │   ├── [id]/
│   │   │   │   ├── +page.svelte
│   │   │   │   ├── +page.server.ts
│   │   │   │   ├── legal/+page.svelte
│   │   │   │   ├── contact/+page.svelte
│   │   │   │   ├── operations/+page.svelte
│   │   │   │   ├── finance/+page.svelte
│   │   │   │   └── history/+page.svelte
│   │   │   └── new/+page.svelte
│   │   ├── reports/
│   │   │   └── +page.svelte
│   │   └── admin/
│   │       └── +page.svelte
│   ├── app.html
│   └── app.d.ts
├── static/
│   └── images/
├── .env
├── package.json
├── svelte.config.js
├── tsconfig.json
└── vite.config.ts
