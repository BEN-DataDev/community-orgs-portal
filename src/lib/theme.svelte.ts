/**
 * The single source of truth for theming.
 *
 * This replaces three uncoordinated mechanisms: `ThemeToggle` wrote a `darkMode`
 * key and toggled `.dark` on <html>, `ThemeSelector` wrote a `theme` key and set
 * `data-theme` on <body>, and `stores/app.ts` listened for storage events on a
 * `THEME_PREFERENCE_KEY` that nothing ever wrote.
 *
 * Two independent axes:
 *   - `name` selects a Skeleton palette, applied as `data-theme` on <html>.
 *   - `dark` toggles the `.dark` class, which `app.css` binds the dark variant to.
 *
 * The storage keys are the ones the old components already used, so existing
 * preferences carry over. `app.html` reads the same keys in an inline script so
 * the choice is applied before first paint rather than flashing on mount.
 */

export const THEME_STORAGE_KEY = 'theme';
export const DARK_MODE_STORAGE_KEY = 'darkMode';

export const DEFAULT_THEME = 'seafoam';

export const THEMES = [
	{ value: 'concord', name: 'Concord' },
	{ value: 'legacy', name: 'Legacy' },
	{ value: 'mona', name: 'Mona' },
	{ value: 'rocket', name: 'Rocket' },
	{ value: 'seafoam', name: 'Seafoam' },
	{ value: 'vox', name: 'Vox' },
	{ value: 'wintry', name: 'Wintry' },
	{ value: 'cii', name: 'CII' }
] as const;

const THEME_VALUES = THEMES.map((theme) => theme.value) as readonly string[];

function isKnownTheme(value: string | null): value is string {
	return value !== null && THEME_VALUES.includes(value);
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

class ThemeState {
	name = $state(DEFAULT_THEME);
	dark = $state(false);

	/** Reads stored preferences, falling back to the OS setting for dark mode. */
	init() {
		const storedTheme = readStored(THEME_STORAGE_KEY);
		this.name = isKnownTheme(storedTheme) ? storedTheme : DEFAULT_THEME;

		const storedDark = readStored(DARK_MODE_STORAGE_KEY);
		/**
		 * Checked for null before comparing. The old code wrote
		 * `getItem(...) === 'true' ?? matchMedia(...)`, where the left side is
		 * always a boolean, so `??` never fell through and the OS preference was
		 * dead code.
		 */
		this.dark =
			storedDark === null
				? window.matchMedia('(prefers-color-scheme: dark)').matches
				: storedDark === 'true';

		this.apply();
	}

	setName(value: string) {
		if (!isKnownTheme(value)) return;
		this.name = value;
		writeStored(THEME_STORAGE_KEY, value);
		this.apply();
	}

	toggleDark() {
		this.dark = !this.dark;
		writeStored(DARK_MODE_STORAGE_KEY, String(this.dark));
		this.apply();
	}

	private apply() {
		const root = document.documentElement;
		root.setAttribute('data-theme', this.name);
		root.classList.toggle('dark', this.dark);
	}
}

export const theme = new ThemeState();
