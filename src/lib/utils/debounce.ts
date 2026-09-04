/**
 * Delays `func` until `wait` ms have passed without another call.
 *
 * `Args` is inferred from the wrapped function rather than declared as `any[]`,
 * so call sites keep their argument types. The timer type comes from
 * `setTimeout` itself — `NodeJS.Timeout` is wrong in the browser.
 */
export function debounce<Args extends unknown[]>(
	func: (...args: Args) => unknown,
	wait: number
): (...args: Args) => void {
	let timeout: ReturnType<typeof setTimeout> | undefined;

	return function executedFunction(...args: Args) {
		clearTimeout(timeout);
		timeout = setTimeout(() => func(...args), wait);
	};
}
