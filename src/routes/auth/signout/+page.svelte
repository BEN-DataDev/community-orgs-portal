<script lang="ts">
	import type { PageProps } from './$types';
	let { form }: PageProps = $props();
</script>

<svelte:head>
	<title>Sign out</title>
</svelte:head>

<div class="card preset-tonal mx-auto my-4 w-full max-w-100 space-y-3 p-5 shadow-md">
	<h1 class="text-xl font-bold">Sign out</h1>
	<p>Sign out of this session. Your other sessions will stay signed in.</p>
	{#if form?.error}<p role="alert">{form.error}</p>{/if}
	<form method="POST">
		<button type="submit" class="btn preset-filled-primary-500">Sign out</button>
	</form>
</div>
