/**
 * Reactive media queries.
 *
 * Layout that cannot be expressed with Tailwind breakpoints alone — where a
 * component takes a *different prop* rather than different classes — needs the
 * breakpoint as reactive state. `AppNavigation` is the case that motivates
 * this: one `Navigation` renders as a bar, rail or sidebar depending on width.
 *
 * Prefer plain `md:`/`lg:` utilities wherever they suffice; reach for this only
 * when JavaScript genuinely needs to know the breakpoint.
 */

import { BROWSER } from 'esm-env';

/** Tailwind's default breakpoints, so JS and CSS agree on where things change. */
export const BREAKPOINT = {
	sm: '40rem',
	md: '48rem',
	lg: '64rem',
	xl: '80rem',
	'2xl': '96rem'
} as const;

export type Breakpoint = keyof typeof BREAKPOINT;

/**
 * Tracks a media query. Call `subscribe()` from `onMount` and invoke the
 * returned teardown on destroy.
 *
 * On the server, and before `subscribe()` runs, `matches` is the `initial`
 * value. SSR cannot know the viewport, so pick the value that renders a
 * sensible first paint — mobile-first, that is usually `false`.
 */
export class MediaQuery {
	matches = $state(false);

	#query: string;

	constructor(query: string, initial = false) {
		this.#query = query;
		this.matches = initial;
	}

	subscribe(): () => void {
		if (!BROWSER) return () => {};

		const list = window.matchMedia(this.#query);
		this.matches = list.matches;

		const onChange = (event: MediaQueryListEvent) => {
			this.matches = event.matches;
		};
		list.addEventListener('change', onChange);

		return () => list.removeEventListener('change', onChange);
	}
}

/** `true` at or above the given Tailwind breakpoint. */
export function minWidth(breakpoint: Breakpoint, initial = false): MediaQuery {
	return new MediaQuery(`(min-width: ${BREAKPOINT[breakpoint]})`, initial);
}
