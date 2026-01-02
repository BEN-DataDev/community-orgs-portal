import { skeleton } from '@skeletonlabs/skeleton/plugin';
import * as themes from '@skeletonlabs/skeleton/themes';
import ciiTheme from './cii-theme.ts';

import type { Config } from 'tailwindcss';

export default {
	plugins: [
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
