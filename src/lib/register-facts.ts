import { z } from 'zod';

export function safePublicUrl(value: string | null): string | null {
	if (!value) return null;
	const hasControlCharacter = [...value].some(
		(char) => char.charCodeAt(0) < 32 || char.charCodeAt(0) === 127
	);
	if (hasControlCharacter || /[\s\\]/.test(value)) return null;
	try {
		const url = new URL(value);
		return ['https:', 'http:'].includes(url.protocol) && !url.username && !url.password
			? url.href
			: null;
	} catch {
		return null;
	}
}
const address = z
	.object({
		type: z.string().optional(),
		line_1: z.string().optional(),
		line_2: z.string().optional(),
		line_3: z.string().optional(),
		locality: z.string().optional(),
		state: z.string().optional(),
		postcode: z.string().optional(),
		country: z.string().optional()
	})
	.strict();
const calendar = z
	.object({ month: z.number().int().min(1).max(12), day: z.number().int().min(1).max(31) })
	.strict();
export const registerFactSchema = z.object({
	field: z.string(),
	section: z.enum(['Overview', 'Legal', 'Contact', 'Operations', 'Finance', 'Governance']),
	label: z.string(),
	kind: z.enum(['string', 'date', 'boolean', 'integer', 'address', 'month_day']),
	value: z.union([z.string(), z.boolean(), z.number().int().nonnegative(), address, calendar]),
	source_title: z.string(),
	source_url: z.string().nullable().transform(safePublicUrl),
	resource_id: z.string(),
	licence: z.string().nullable(),
	licence_url: z.string().nullable().transform(safePublicUrl),
	observed_at: z.string().datetime({ offset: true }),
	published_at: z.string().datetime({ offset: true }),
	effective_date: z.string().nullable(),
	unchanged_since_import: z.boolean(),
	retained_address_components: z.array(z.string())
});
export const registerFactsSchema = z.array(registerFactSchema);
export type RegisterFact = z.infer<typeof registerFactSchema>;
export type RegisterSection = RegisterFact['section'];
export function factGroup(field: string) {
	if (field.startsWith('purposes.')) return 'Charitable purposes';
	if (field.startsWith('beneficiaries.')) return 'Beneficiaries';
	if (field.startsWith('operating_jurisdictions.')) return 'Operating states and territories';
	return 'Register details';
}
export function factValue(fact: RegisterFact): string {
	if (typeof fact.value === 'boolean') return fact.value ? 'Yes' : 'No';
	if (typeof fact.value !== 'object') return String(fact.value);
	if ('month' in fact.value) {
		return `${fact.value.day} ${['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][fact.value.month - 1]}`;
	}
	const labels: Record<string, string> = {
		type: 'Address type',
		line_1: 'Line 1',
		line_2: 'Line 2',
		line_3: 'Line 3',
		locality: 'Locality',
		state: 'State / territory',
		postcode: 'Postcode',
		country: 'Country'
	};
	const value = fact.value as Record<string, string>;
	return Object.entries(labels)
		.filter(([key]) => value[key] !== undefined)
		.map(([key, label]) => `${label}: ${value[key]}`)
		.join('\n');
}
export function observationDate(value: string) {
	return new Intl.DateTimeFormat('en-AU', {
		timeZone: 'UTC',
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	}).format(new Date(value));
}
