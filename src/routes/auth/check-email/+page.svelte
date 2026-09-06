<script lang="ts">
	import { resolve } from '$app/paths';
</script>

<svelte:head>
	<title>Confirm your email</title>
</svelte:head>

<div class="card preset-tonal mx-auto my-4 w-full max-w-100 space-y-3 p-5 shadow-md">
	<h1 class="text-xl font-bold">Confirm your email</h1>
	<p>
		We have sent you a confirmation link. Open it to finish setting up your account, then sign in.
	</p>
	<a class="btn preset-filled-primary-500" href={resolve('/auth/signin')}>Back to sign in</a>
</div>
