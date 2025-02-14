import { join } from 'path';
import aspectRatio from '@tailwindcss/aspect-ratio';
import containerQueries from '@tailwindcss/container-queries';
import forms from '@tailwindcss/forms';
import typography from '@tailwindcss/typography';
import { skeleton } from '@skeletonlabs/skeleton/plugin';
import * as themes from '@skeletonlabs/skeleton/themes';
import ciiTheme from './cii-theme.ts';

import type { Config } from 'tailwindcss';

export default {
	darkMode: 'selector',
	content: [
		'./src/**/*.{html,js,svelte,ts}',
		join(require.resolve('@skeletonlabs/skeleton-svelte'), '../**/*.{html,js,svelte,ts}')
	],

	theme: {
		extend: {}
	},

	plugins: [
		typography,
		forms,
		containerQueries,
		aspectRatio,
		skeleton({
			themes: [
				// Preset Theme(s)
				themes.concord,
				themes.legacy,
				themes.mona,
				themes.rocket,
				themes.seafoam,
				themes.vox,
				themes.wintry,
				// Custom Theme(s)
				ciiTheme
			]
		})
	]
} satisfies Config;
