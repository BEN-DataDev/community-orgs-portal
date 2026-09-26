<script lang="ts">
	import { afterNavigate } from '$app/navigation';
	import { page } from '$app/state';
	import { onMount } from 'svelte';

	type Notice = { kind: 'success' | 'error'; message: string };
	type ActionData = Record<string, unknown>;

	let pending = $state(false);
	let pendingLabel = $state('Submitting form');
	let notice = $state<Notice | null>(null);
	let activeForm: HTMLFormElement | null = null;
	let activeSubmitter: HTMLElement | null = null;
	let submittedPost = false;
	let previousForm = page.form;

	function text(value: unknown) {
		return typeof value === 'string' && value.trim() ? value.trim() : null;
	}

	function actionMessage(value: unknown, failed: boolean) {
		const data = value && typeof value === 'object' ? (value as ActionData) : null;
		return (
			text(data?.message) ??
			text(data?.error) ??
			(failed ? 'The form could not be submitted. Check the form and try again.' : 'Changes saved.')
		);
	}

	function clearPending() {
		pending = false;
		activeForm?.removeAttribute('aria-busy');
		delete activeForm?.dataset.submitting;
		delete activeSubmitter?.dataset.submitTrigger;
		activeForm = null;
		activeSubmitter = null;
	}

	function finish(value: unknown, status: number) {
		if (!submittedPost) return;
		const failed = status >= 400;
		clearPending();
		notice = { kind: failed ? 'error' : 'success', message: actionMessage(value, failed) };
		submittedPost = false;
	}

	$effect(() => {
		const current = page.form;
		if (current === previousForm) return;
		previousForm = current;
		finish(current, page.status);
	});

	afterNavigate(() => {
		if (!pending) return;
		if (submittedPost && page.form) finish(page.form, page.status);
		else if (submittedPost) {
			const failed = page.status >= 400;
			clearPending();
			notice = {
				kind: failed ? 'error' : 'success',
				message: failed ? 'The form could not be submitted.' : 'Changes saved.'
			};
			submittedPost = false;
		} else clearPending();
	});

	onMount(() => {
		// A non-enhanced action completes through a full reload, so its result is
		// already present on first mount rather than arriving through the effect.
		if (page.form) {
			const failed = page.status >= 400;
			notice = { kind: failed ? 'error' : 'success', message: actionMessage(page.form, failed) };
		}

		const onSubmit = (event: SubmitEvent) => {
			const form = event.target instanceof HTMLFormElement ? event.target : null;
			// Forms without an explicit method in this application are handled by
			// client-only JavaScript and manage their own pending state.
			if (!form || !form.hasAttribute('method')) return;
			if (form.dataset.submitting === 'true') {
				event.preventDefault();
				return;
			}

			activeForm = form;
			activeSubmitter = event.submitter instanceof HTMLElement ? event.submitter : null;
			pendingLabel = activeSubmitter?.textContent?.trim() || 'Submitting form';
			pending = true;
			submittedPost = form.method.toLowerCase() === 'post';
			notice = null;
			form.dataset.submitting = 'true';
			form.setAttribute('aria-busy', 'true');
			if (activeSubmitter) activeSubmitter.dataset.submitTrigger = 'true';
		};

		document.addEventListener('submit', onSubmit, true);
		return () => document.removeEventListener('submit', onSubmit, true);
	});
</script>

{#if pending}
	<div
		class="card preset-tonal-primary fixed right-4 bottom-4 z-100 flex max-w-sm items-center gap-3 p-4 shadow-xl"
		role="status"
		aria-live="polite"
	>
		<span
			aria-hidden="true"
			class="size-5 shrink-0 animate-spin rounded-full border-2 border-current border-t-transparent"
		></span>
		<span><strong>{pendingLabel}</strong><span class="block text-sm">Please wait…</span></span>
	</div>
{:else if notice}
	<div
		class="card fixed right-4 bottom-4 z-100 flex max-w-sm items-start gap-3 p-4 shadow-xl {notice.kind ===
		'success'
			? 'preset-tonal-success'
			: 'preset-tonal-error'}"
		role={notice.kind === 'error' ? 'alert' : 'status'}
		aria-live={notice.kind === 'error' ? 'assertive' : 'polite'}
	>
		<div class="min-w-0 flex-1">
			<strong>{notice.kind === 'success' ? 'Completed' : 'Not completed'}</strong>
			<p class="text-sm break-words">{notice.message}</p>
		</div>
		<button
			class="btn btn-sm"
			type="button"
			aria-label="Dismiss form status"
			onclick={() => (notice = null)}>Dismiss</button
		>
	</div>
{/if}
