<script lang="ts">
	import { captchaRequired } from '$lib/auth/captcha';
	import TurnstileWidget from './TurnstileWidget.svelte';

	interface Props {
		redirectTo?: string;
		label?: string;
	}

	let { redirectTo = '/organisations', label = 'Browse without an account' }: Props = $props();

	let token = $state('');

	/**
	 * Anonymous sign-in is the one flow that must not be reachable without abuse
	 * protection: every attempt writes a row to auth.users, so an unprotected
	 * endpoint is a free way to grow the database. Where the other auth forms
	 * degrade to working without a token, this one hides itself instead.
	 */
	const available = captchaRequired();
</script>

{#if available}
	<form method="POST" action="/auth/anonymous" class="flex flex-col items-center gap-3">
		<input type="hidden" name="redirectTo" value={redirectTo} />
		<input type="hidden" name="captchaToken" value={token} />

		<TurnstileWidget onToken={(received) => (token = received)} />

		<button type="submit" class="btn preset-tonal" disabled={!token}>
			{token ? label : 'Checking your browser...'}
		</button>
	</form>
{/if}
