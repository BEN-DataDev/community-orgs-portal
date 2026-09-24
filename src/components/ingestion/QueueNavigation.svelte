<script lang="ts">
	import { resolve } from '$app/paths';
	let {
		current,
		campaign = '',
		run = '',
		version = ''
	}: { current: string; campaign?: string; run?: string; version?: string } = $props();
	const queues = [
		['validation', 'Validation', '/admin/ingestion/validation'],
		['identity', 'Identity and eligibility', '/admin/ingestion/identity'],
		['changes', 'Field changes', '/admin/ingestion/changes'],
		['releases', 'Release decisions', '/admin/ingestion/releases'],
		['suppressions', 'Suppression and withdrawal', '/admin/ingestion/suppressions']
	] as const;
	function href(path: (typeof queues)[number][2]) {
		const base = resolve(path);
		const params = new URLSearchParams();
		if (campaign) params.set('campaign', campaign);
		if (run) params.set(path.endsWith('/validation') ? 'issue_run' : 'run', run);
		if (version && !path.endsWith('/validation') && !path.endsWith('/releases'))
			params.set('version', version);
		return params.size ? `${base}?${params}` : base;
	}
</script>

{#if campaign}
	<p class="card preset-tonal p-3 text-sm">
		Campaign context: <span class="font-mono break-all">{campaign}</span> ·
		<a class="anchor" href={resolve('/admin/campaigns')}>Return to campaign dashboard</a>
	</p>
{/if}
<nav aria-label="Ingestion decision queues" class="grid gap-2 sm:grid-cols-2 xl:grid-cols-5">
	{#each queues as [key, label, path]}
		<a
			class={`card border-surface-200-800 block border p-3 ${key === current ? 'preset-filled-primary-500' : 'hover:preset-tonal'}`}
			href={href(path)}
			aria-current={key === current ? 'page' : undefined}>{label}</a
		>
	{/each}
</nav>
