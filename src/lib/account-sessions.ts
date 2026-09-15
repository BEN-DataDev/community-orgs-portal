export interface AccountSession {
	session_id: string;
	is_current: boolean;
	signed_in_at: string | null;
	last_refreshed_at: string | null;
	expires_at: string | null;
	user_agent: string | null;
	total_count: number;
}

// UA text is untrusted and often belongs to a server rather than a device.
// Return only recognised labels, never infer a precise device or location.
export function sessionBrowser(agent: string | null): string {
	if (!agent) return 'Browser details unavailable';
	const browser = /Edg(?:e|A|iOS)?\//.test(agent)
		? 'Edge'
		: /(?:OPR|Opera)\//.test(agent)
			? 'Opera'
			: /(?:Firefox|FxiOS)\//.test(agent)
				? 'Firefox'
				: /(?:Chrome|CriOS)\//.test(agent)
					? 'Chrome'
					: /Safari\//.test(agent) && /Version\//.test(agent)
						? 'Safari'
						: null;
	if (!browser) return 'Browser details unavailable';
	const os = /Android/.test(agent)
		? 'Android'
		: /iPhone|iPad|iPod/.test(agent)
			? 'iOS'
			: /Windows/.test(agent)
				? 'Windows'
				: /Macintosh|Mac OS X/.test(agent)
					? 'macOS'
					: /Linux/.test(agent)
						? 'Linux'
						: null;
	return os ? `${browser} on ${os}` : browser;
}

export function sessionTime(value: string | null): string {
	if (!value || !Number.isFinite(Date.parse(value))) return 'Unavailable';
	return (
		new Intl.DateTimeFormat('en-AU', {
			dateStyle: 'medium',
			timeStyle: 'short',
			timeZone: 'UTC'
		}).format(new Date(value)) + ' UTC'
	);
}
