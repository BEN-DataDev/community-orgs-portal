<script lang="ts">
	import { resolve } from '$app/paths';
	import QueueNavigation from '$components/ingestion/QueueNavigation.svelte';
	import ValidationIssues from '$components/ingestion/ValidationIssues.svelte';
	import type { PageProps } from './$types';
	let { data, form }: PageProps = $props();
</script>

<svelte:head><title>Validation queue</title></svelte:head>
<div class="space-y-6">
	<header class="space-y-2">
		<a class="anchor" href={resolve('/admin/ingestion')}>All ingestion queues</a>
		<h1 class="text-2xl font-bold">Validation queue</h1>
		<p>Primary decision: resolve staged-data validation issues.</p>
		<p class="text-sm">Next responsible role: <strong>Data Steward</strong>.</p>
	</header>
	<QueueNavigation current="validation" campaign={data.campaign} run={data.filter.run} />
	{#if form?.message}<p role="status" class="card preset-tonal p-4">{form.message}</p>{/if}
	<ValidationIssues
		queue={data.queue}
		filter={data.filter}
		readiness={data.readiness}
		{form}
		campaign={data.campaign}
	/>
</div>
