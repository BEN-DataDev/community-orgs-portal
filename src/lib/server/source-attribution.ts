import { z } from 'zod';
export function publicSourceUrl(value: string | null): string | null {
	if (!value) return null;
	try {
		const url = new URL(value);
		return ['https:', 'http:'].includes(url.protocol) && !url.username && !url.password
			? url.href
			: null;
	} catch {
		return null;
	}
}
export const attributionSchema = z.array(
	z.object({
		source_id: z.string(),
		resource_id: z.string(),
		title: z.string(),
		url: z.string().nullable().transform(publicSourceUrl),
		licence: z.string().nullable(),
		licence_url: z.string().nullable().transform(publicSourceUrl),
		observed_at: z.string(),
		published_at: z.string(),
		field: z.string(),
		unchanged_since_import: z.boolean()
	})
);
