import { readable } from 'svelte/store';

export type Theme = 'light' | 'dark';

const THEME_PREFERENCE_KEY = 'THEME_PREFERENCE_KEY';

export const themeStore = readable<Theme>('light', (set) => {
	let observer: MutationObserver | undefined;
	let currentTheme: Theme = 'light';

	const updateTheme = () => {
		const isDark = document.documentElement.classList.contains('dark');
		const newTheme: Theme = isDark ? 'dark' : 'light';
		if (newTheme !== currentTheme) {
			currentTheme = newTheme;
			set(currentTheme);
		}
	};

	if (typeof window !== 'undefined') {
		// Initial theme set
		updateTheme();

		// Watch for changes in the 'dark' class on the html element
		observer = new MutationObserver(updateTheme);
		observer.observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });

		// Watch for changes in localStorage
		const handleStorage = (event: StorageEvent) => {
			if (event.key === THEME_PREFERENCE_KEY) {
				updateTheme();
			}
		};
		window.addEventListener('storage', handleStorage);

		// Return cleanup function
		return () => {
			observer?.disconnect();
			window.removeEventListener('storage', handleStorage);
		};
	}

	// Return a no-op cleanup function if not in browser environment
	return () => {};
});
