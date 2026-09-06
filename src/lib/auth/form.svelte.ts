import { applyAction } from '$app/forms';
import type { SubmitFunction } from '@sveltejs/kit';

export interface AuthFormErrors {
	general?: string;
	email?: string;
	password?: string;
	code?: string;
	[key: string]: string | undefined;
}

/**
 * Shared submit handling for the auth forms.
 *
 * Every auth page previously carried its own near-identical copy of this, and
 * each copy tracked errors twice — once from an `$effect` on the `form` prop and
 * once from the enhance callback — with only the second one rendered. There is
 * one source of errors here.
 *
 * It also fixes the ordering bug in those copies: they set `loading = true`
 * inside the result callback, which is *after* the request completes, so the
 * submit button never actually disabled while the request was in flight.
 */
export function createAuthForm() {
	let loading = $state(false);
	let errors = $state<AuthFormErrors>({});

	const enhance: SubmitFunction = () => {
		loading = true;
		errors = {};

		return async ({ result, update }) => {
			if (result.type === 'redirect') {
				/**
				 * Stay in the loading state: the navigation is what ends this
				 * submission, and re-enabling the button first lets someone
				 * double-submit into the redirect.
				 */
				await applyAction(result);
				return;
			}

			if (result.type === 'error') {
				errors = { general: 'A network error occurred. Please try again.' };
			} else if (result.type === 'failure') {
				const data = result.data as { errors?: AuthFormErrors; error?: string } | undefined;
				errors = data?.errors ?? { general: data?.error ?? 'That did not work. Please try again.' };
			} else {
				await update();
			}

			loading = false;
		};
	};

	return {
		get loading() {
			return loading;
		},
		get errors() {
			return errors;
		},
		enhance
	};
}
