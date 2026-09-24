<script lang="ts">
	import { resolve } from '$app/paths';
	import QueueNavigation from '$components/ingestion/QueueNavigation.svelte';
</script>

<svelte:head><title>Ingestion work queues</title></svelte:head>
<div class="space-y-6">
	<header class="space-y-2">
		<a class="anchor" href={resolve('/admin')}>Back to Admin</a>
		<h1 class="text-2xl font-bold">Ingestion work queues</h1>
		<p>Choose the decision queue that matches the work you need to complete.</p>
		<p class="text-sm">
			Each queue has one decision type and identifies the next responsible role.
		</p>
	</header>
	<QueueNavigation current="" />
	<div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
		<a class="card preset-tonal space-y-2 p-4" href={resolve('/admin/ingestion/jobs')}>
			<h2 class="font-semibold">Acquisition jobs</h2>
			<p>Configure and monitor source acquisition.</p>
		</a>
		<a class="card preset-tonal space-y-2 p-4" href={resolve('/admin/campaigns')}>
			<h2 class="font-semibold">Campaign context</h2>
			<p>Review pinned evidence, progress and blockers.</p>
		</a>
	</div>
</div>
