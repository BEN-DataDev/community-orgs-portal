<script lang="ts">
	import { resolve } from '$app/paths';

	interface Props {
		title: string;
		message: string;
		/** Label and destination for the primary action. */
		actionLabel?: string;
		actionHref?: string;
	}

	let { title, message, actionLabel = 'Back to home', actionHref = resolve('/') }: Props = $props();
</script>

<div class="card preset-tonal mx-auto my-4 w-full max-w-100 space-y-3 p-5 text-center shadow-md">
	<h1 class="h3">{title}</h1>
	<p class="text-surface-700-300">{message}</p>
	<a class="btn preset-filled-primary-500" href={actionHref}>{actionLabel}</a>
</div>
