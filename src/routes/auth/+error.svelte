<script lang="ts">
	import { resolve } from '$app/paths';
	import { page } from '$app/state';
</script>

<div class="card preset-tonal mx-auto my-4 w-full max-w-100 space-y-3 p-5 text-center shadow-md">
	<h1 class="h3">{page.status}</h1>
	<p class="text-surface-700-300">{page.error?.message ?? 'Something went wrong.'}</p>
	<a class="btn preset-filled-primary-500" href={resolve('/')}>Back to home</a>
</div>
