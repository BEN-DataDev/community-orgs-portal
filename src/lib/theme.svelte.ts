/**
 * The single source of truth for light/dark mode.
 *
 * The app ships one Skeleton theme (`pine`), applied as a static `data-theme`
 * attribute in app.html. The only runtime axis is the colour mode, which has
 * three states:
 *
 *   - `system` (default) — follows the OS, live, via a media-query listener.
 *   - `light` / `dark`   — an explicit override that pins the mode.
 *
 * `app.html` resolves the same key in an inline script before first paint, so
 * the mode is applied rather than flashing on mount. Keep the two in sync.
 */

export const MODE_STORAGE_KEY = 'colorMode';

/** The key written by the previous two-state toggle, read once for migration. */
const LEGACY_DARK_KEY = 'darkMode';

const DARK_QUERY = '(prefers-color-scheme: dark)';

export type ColorMode = 'light' | 'dark' | 'system';

export const DEFAULT_MODE: ColorMode = 'system';

/** The order the toggle cycles through. */
const MODE_CYCLE: readonly ColorMode[] = ['system', 'light', 'dark'];

function isColorMode(value: string | null): value is ColorMode {
	return value === 'light' || value === 'dark' || value === 'system';
}

/**
 * `localStorage` throws in some privacy modes, so every access is guarded and
 * falls back to the default rather than breaking the page.
 */
function readStored(key: string): string | null {
	try {
		return localStorage.getItem(key);
	} catch {
		return null;
	}
}

function writeStored(key: string, value: string): void {
	try {
		localStorage.setItem(key, value);
	} catch {
		// A preference we cannot persist is not worth failing a render over.
	}
}

function removeStored(key: string): void {
	try {
		localStorage.removeItem(key);
	} catch {
		// As above.
	}
}

class ThemeState {
	mode = $state<ColorMode>(DEFAULT_MODE);

	/** Tracks the OS preference so `system` can resolve without re-querying. */
	private systemDark = $state(false);

	/** The mode actually rendered, once `system` is resolved against the OS. */
	readonly dark = $derived(this.mode === 'system' ? this.systemDark : this.mode === 'dark');

	/**
	 * Reads the stored mode and starts following the OS preference.
	 * Returns a teardown that removes the media-query listener; call it from
	 * the `onMount` cleanup in the root layout.
	 */
	init(): () => void {
		const stored = readStored(MODE_STORAGE_KEY);

		if (isColorMode(stored)) {
			this.mode = stored;
		} else {
			// Carry over a preference set by the previous boolean toggle, so
			// anyone who had chosen a mode keeps it.
			const legacy = readStored(LEGACY_DARK_KEY);
			if (legacy === 'true' || legacy === 'false') {
				this.mode = legacy === 'true' ? 'dark' : 'light';
				writeStored(MODE_STORAGE_KEY, this.mode);
			} else {
				this.mode = DEFAULT_MODE;
			}
			removeStored(LEGACY_DARK_KEY);
		}

		const query = window.matchMedia(DARK_QUERY);
		this.systemDark = query.matches;
		this.apply();

		/**
		 * The old implementation read the media query once and never again, so
		 * `system` silently stopped tracking the OS after first paint. This
		 * listener is what makes the `system` state mean anything.
		 */
		const onChange = (event: MediaQueryListEvent) => {
			this.systemDark = event.matches;
			this.apply();
		};
		query.addEventListener('change', onChange);

		return () => query.removeEventListener('change', onChange);
	}

	setMode(value: ColorMode) {
		this.mode = value;
		writeStored(MODE_STORAGE_KEY, value);
		this.apply();
	}

	/** Steps `system → light → dark → system`. */
	cycle() {
		const next = MODE_CYCLE[(MODE_CYCLE.indexOf(this.mode) + 1) % MODE_CYCLE.length];
		this.setMode(next);
	}

	private apply() {
		document.documentElement.classList.toggle('dark', this.dark);
	}
}

export const theme = new ThemeState();
