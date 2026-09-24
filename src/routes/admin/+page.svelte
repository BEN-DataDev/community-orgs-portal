<script lang="ts">
	import { resolve } from '$app/paths';
	import { ArrowRight, FileInput } from 'lucide-svelte';
	import type { PageProps } from './$types';
	let { data }: PageProps = $props();
</script>

<svelte:head><title>Admin</title></svelte:head>
<div class="space-y-6">
	<header>
		<h1 class="text-2xl font-bold">Admin</h1>
		<p class="text-surface-600-400">Choose an administration task.</p>
		<p class="text-surface-600-400">
			Portal scope revision {data.portal.scopeRevision ?? 'not configured'} · {data.portal
				.scopePostcodes.length} postcodes
		</p>
	</header>
	<section aria-label="Administration tasks" class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
		{#if data.isSiteAdmin}
			<a
				href={resolve('/admin/portal/scope')}
				class="card border-surface-200-800 hover:preset-tonal space-y-3 border p-5 focus-visible:outline-2 focus-visible:outline-offset-2"
			>
				<h2 class="text-lg font-semibold">Portal scope</h2>
				<p>Review the postcode boundary and create an immutable scope revision.</p>
				<span class="font-medium">Open portal scope →</span>
			</a>
			<a
				href={resolve('/admin/sources')}
				class="card border-surface-200-800 hover:preset-tonal space-y-3 border p-5 focus-visible:outline-2 focus-visible:outline-offset-2"
			>
				<h2 class="text-lg font-semibold">Source approvals</h2>
				<p>Review source evidence and licences, then enable or pause a data source.</p>
				<span class="font-medium">Open source approvals →</span>
			</a>
		{/if}

		{#if data.isIngestionOperator}
			<a
				href={resolve('/admin/ingestion')}
				class="card border-surface-200-800 hover:preset-tonal space-y-3 border p-5 focus-visible:outline-2 focus-visible:outline-offset-2"
			>
				<FileInput size={24} aria-hidden="true" />
				<h2 class="text-lg font-semibold">Import review</h2>
				<p class="text-surface-600-400">
					Review imported records, compare organisation matches and approve selected changes for
					publication.
				</p>
				<span class="flex items-center gap-2 font-medium"
					>Open import review <ArrowRight size={16} aria-hidden="true" /></span
				>
			</a>
		{:else}
			<p class="text-surface-600-400">
				No administration tasks are currently available for your account.
			</p>
		{/if}
	</section>
</div>
