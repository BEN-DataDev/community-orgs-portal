<script lang="ts">
	interface Props {
		password: string;
	}

	let { password }: Props = $props();

	/**
	 * The zxcvbn dictionaries are several hundred kilobytes of word lists. They
	 * are only needed once someone actually types a password, so they are pulled
	 * in with a dynamic `import()` on the first keystroke instead of riding
	 * along in the route's initial bundle.
	 */
	let scorer: Promise<(password: string) => { score: number }> | null = null;

	async function loadScorer() {
		const [core, common, en] = await Promise.all([
			import('@zxcvbn-ts/core'),
			import('@zxcvbn-ts/language-common'),
			import('@zxcvbn-ts/language-en')
		]);

		core.zxcvbnOptions.setOptions({
			translations: en.translations,
			graphs: common.adjacencyGraphs,
			dictionary: { ...common.dictionary, ...en.dictionary }
		});

		return core.zxcvbn;
	}

	const labels = ['Weak', 'Weak', 'Fair', 'Good', 'Strong'] as const;
	const tones = ['error', 'error', 'warning', 'tertiary', 'success'] as const;

	let score = $state<number | null>(null);

	$effect(() => {
		if (!password) {
			score = null;
			return;
		}

		/**
		 * Remember what was typed when this call started: the dictionaries load
		 * asynchronously, so a slower earlier keystroke must not overwrite the
		 * verdict for what is in the field now.
		 */
		const scored = password;
		scorer ??= loadScorer();

		scorer.then((zxcvbn) => {
			if (scored !== password) return;
			score = zxcvbn(scored).score;
		});
	});

	const label = $derived(score === null ? '' : labels[score]);
	const tone = $derived(score === null ? null : tones[score]);
	const percent = $derived(score === null ? 0 : ((score + 1) / 5) * 100);
</script>

<div class="mt-2 mb-4">
	<div class="mb-1 flex justify-between">
		<span class="text-sm font-medium">Password strength</span>
		<span
			class="text-sm font-medium"
			class:text-error-500={tone === 'error'}
			class:text-warning-500={tone === 'warning'}
			class:text-tertiary-500={tone === 'tertiary'}
			class:text-success-500={tone === 'success'}
		>
			{label}
		</span>
	</div>
	<div class="bg-surface-300-600 h-2.5 w-full rounded-full">
		<div
			class="h-2.5 rounded-full transition-all duration-300 ease-in-out"
			class:bg-error-500={tone === 'error'}
			class:bg-warning-500={tone === 'warning'}
			class:bg-tertiary-500={tone === 'tertiary'}
			class:bg-success-500={tone === 'success'}
			style="width: {percent}%"
		></div>
	</div>
</div>
