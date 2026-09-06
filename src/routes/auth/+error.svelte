<script lang="ts">
	import { page } from '$app/state';
	import AuthErrorCard from '$components/ui/auth/AuthErrorCard.svelte';
</script>

<AuthErrorCard
	title={String(page.status)}
	message={page.error?.message ?? 'Something went wrong.'}
/>
