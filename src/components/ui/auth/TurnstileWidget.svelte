<script lang="ts">
	import { env } from '$env/dynamic/public';

	interface Props {
		/** Receives the token once Cloudflare issues one, and '' when it expires. */
		onToken: (token: string) => void;
	}

	let { onToken }: Props = $props();

	/**
	 * Supabase's CAPTCHA setting is project-wide: turning it on for anonymous
	 * sign-ins turns it on for `signUp`, `signInWithPassword`, `signInWithOtp` and
	 * `resetPasswordForEmail` as well, and each of those then rejects any request
	 * without a token. So this widget belongs on every auth form, not only on the
	 * guest button that motivated enabling it.
	 *
	 * Renders nothing when PUBLIC_TURNSTILE_SITE_KEY is unset. Cloudflare publish
	 * always-passing test keys for local development — see .env.example.
	 */
	const siteKey = env.PUBLIC_TURNSTILE_SITE_KEY;

	let container: HTMLDivElement | undefined = $state();
	let failed = $state(false);

	interface TurnstileApi {
		render: (
			el: HTMLElement,
			options: {
				sitekey: string;
				callback: (token: string) => void;
				'expired-callback': () => void;
				'error-callback': () => void;
				theme: 'auto';
			}
		) => void;
	}

	const SCRIPT_SRC = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';

	$effect(() => {
		if (!siteKey || !container) return;

		const key = siteKey;
		const el = container;
		let cancelled = false;

		function render(api: TurnstileApi) {
			if (cancelled) return;
			api.render(el, {
				sitekey: key,
				callback: (token) => onToken(token),
				/**
				 * Tokens are single-use and expire after five minutes. Clearing on
				 * expiry re-disables the submit button rather than letting the form
				 * post a token the Auth server will reject.
				 */
				'expired-callback': () => onToken(''),
				'error-callback': () => onToken(''),
				theme: 'auto'
			});
		}

		const loaded = (window as unknown as { turnstile?: TurnstileApi }).turnstile;
		if (loaded) {
			render(loaded);
			return;
		}

		/**
		 * One script tag per page, even when several widgets mount: the API is a
		 * global, and loading it twice re-runs its auto-scan.
		 */
		let script = document.querySelector<HTMLScriptElement>(`script[src="${SCRIPT_SRC}"]`);
		if (!script) {
			script = document.createElement('script');
			script.src = SCRIPT_SRC;
			script.async = true;
			document.head.appendChild(script);
		}

		const onLoad = () => {
			const api = (window as unknown as { turnstile?: TurnstileApi }).turnstile;
			if (api) render(api);
		};
		const onError = () => (failed = true);

		script.addEventListener('load', onLoad);
		script.addEventListener('error', onError);

		return () => {
			cancelled = true;
			script?.removeEventListener('load', onLoad);
			script?.removeEventListener('error', onError);
		};
	});
</script>

{#if siteKey}
	<div bind:this={container}></div>
	{#if failed}
		<p class="text-error-500 text-sm">
			The verification widget could not load. Check your connection and reload the page.
		</p>
	{/if}
{/if}
