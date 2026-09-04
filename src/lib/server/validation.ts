import { z } from 'zod';
import type { Json } from '$lib/db.types';

/**
 * Schemas for every form action in the application.
 *
 * Actions must never spread `Object.fromEntries(formData)` into a Supabase
 * write: that lets a caller set any column the database grants, including the
 * `inserted_by` / `last_edited_by` audit columns and the primary key. Each
 * schema below names exactly the columns its form is allowed to touch, and
 * `z.object` strips everything else.
 *
 * `org_id` is deliberately absent from all of them — it is read from the route
 * parameter, never from the request body.
 */

/** Empty text inputs arrive as '', which should become SQL NULL, not ''. */
const optionalText = z
	.string()
	.trim()
	.transform((value) => (value === '' ? null : value));

const requiredText = z.string().trim().min(1, 'This field is required');

const optionalDate = z
	.string()
	.trim()
	.refine((value) => value === '' || !Number.isNaN(Date.parse(value)), 'Enter a valid date')
	.transform((value) => (value === '' ? null : value));

const requiredDate = z
	.string()
	.trim()
	.refine((value) => !Number.isNaN(Date.parse(value)), 'Enter a valid date');

const optionalInteger = z
	.string()
	.trim()
	.refine((value) => value === '' || /^\d+$/.test(value), 'Enter a whole number')
	.transform((value) => (value === '' ? null : Number(value)));

const optionalAmount = z
	.string()
	.trim()
	.refine((value) => value === '' || /^\d+(\.\d{1,2})?$/.test(value), 'Enter an amount')
	.transform((value) => (value === '' ? null : Number(value)));

const optionalCoordinate = z
	.string()
	.trim()
	.refine((value) => value === '' || /^-?\d+(\.\d+)?$/.test(value), 'Enter a decimal number')
	.transform((value) => (value === '' ? null : Number(value)));

/** Comma-separated input backing a Postgres text[] column. */
const optionalTextArray = z
	.string()
	.transform((value) =>
		value
			.split(',')
			.map((entry) => entry.trim())
			.filter(Boolean)
	)
	.transform((entries) => (entries.length === 0 ? null : entries));

/** Hidden inputs carrying JSON built up by the form's own controls. */
const optionalJson = z
	.string()
	.trim()
	.transform((value, ctx): Json | null => {
		if (value === '') return null;
		try {
			return JSON.parse(value) as Json;
		} catch {
			ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Could not read this field' });
			return z.NEVER;
		}
	});

/** Checkboxes submit 'on' when ticked and are absent otherwise. */
const optionalBoolean = z
	.union([z.literal('on'), z.literal('true'), z.literal('false'), z.literal('')])
	.optional()
	.transform((value) => {
		if (value === undefined || value === '') return null;
		return value === 'on' || value === 'true';
	});

/**
 * `contact_info.phone` is a jsonb column. A single text input is stored as
 * `{ "primary": "..." }` so the shape stays open for alternate numbers later.
 */
const optionalPhone = z
	.string()
	.trim()
	.optional()
	.transform((value): Json | null => (value ? { primary: value } : null));

/**
 * `organisations.is_public` is NOT NULL, and its checkbox is always rendered,
 * so an absent value means false rather than "not specified".
 */
const requiredCheckbox = z
	.union([z.literal('on'), z.literal('true')])
	.optional()
	.transform((value) => value !== undefined);

export const organisationSchema = z.object({
	entity_name: requiredText,
	description: optionalText.optional(),
	date_established: optionalDate.optional(),
	is_public: requiredCheckbox
});

export const aliasSchema = z.object({
	alias: requiredText,
	alias_type: z.enum(['Business Name', 'Trading Name'])
});

export const contactSchema = z.object({
	email: z
		.union([z.literal(''), z.string().trim().email('Enter a valid email address')])
		.optional(),
	phone: optionalPhone,
	website: z.union([z.literal(''), z.string().trim().url('Enter a valid URL')]).optional(),
	physical_address: optionalText.optional(),
	postal_address: optionalText.optional(),
	social_media: optionalJson.optional()
});

export const legalSchema = z.object({
	entity_type: optionalText.optional(),
	charity_type: optionalText.optional(),
	abn: optionalText.optional(),
	abn_status: optionalBoolean,
	abn_activated: optionalDate.optional(),
	abn_last_updated: optionalDate.optional(),
	acn: optionalText.optional(),
	acnc_status: optionalBoolean,
	acnc_registered: optionalBoolean,
	acnc_registered_date: optionalDate.optional(),
	incorporation_number: optionalText.optional(),
	incorporation_status: optionalBoolean,
	incorporation_registration_date: optionalDate.optional(),
	tax_concession_endorsement: optionalDate.optional(),
	gst_concession_endorsement_date: optionalText.optional(),
	dgr_endorsement: optionalBoolean,
	last_annual_return_date: optionalDate.optional(),
	insurance_details: optionalJson.optional()
});

export const documentSchema = z.object({
	name: requiredText,
	url: z.string().trim().url('Enter a valid URL'),
	category: optionalText.optional()
});

export const financialSchema = z.object({
	annual_budget: optionalAmount.optional(),
	financial_year_end: optionalDate.optional(),
	last_audit_date: optionalDate.optional(),
	funding_sources: optionalTextArray.optional(),
	auditor_details: optionalJson.optional()
});

export const operationsSchema = z.object({
	staff_count_paid: optionalInteger.optional(),
	staff_count_volunteer: optionalInteger.optional(),
	operating_hours: optionalJson.optional(),
	service_area: optionalText.optional(),
	languages_supported: optionalTextArray.optional(),
	accessibility_features: optionalTextArray.optional(),
	target_demographics: optionalText.optional()
});

export const locationSchema = z.object({
	name: requiredText,
	address: optionalText.optional(),
	location_type: optionalText.optional(),
	latitude: optionalCoordinate.optional(),
	longitude: optionalCoordinate.optional()
});

export const relationshipSchema = z.object({
	partner_org: requiredText,
	relationship_type: requiredText,
	start_date: requiredDate,
	end_date: optionalDate.optional()
});

export const historySchema = z.object({
	founding_members: optionalTextArray.optional(),
	milestone_date: requiredDate,
	milestone_description: requiredText,
	structural_changes: optionalJson.optional()
});

/**
 * Turns a parsed form into the column set to write.
 *
 * Fields the form did not render are `undefined` and are dropped, so a form
 * that edits three columns leaves the rest of the row untouched rather than
 * blanking it. Fields that were rendered but left empty become SQL NULL.
 */
export function toColumns<T extends Record<string, unknown>>(values: T): Partial<T> {
	return Object.fromEntries(
		Object.entries(values)
			.filter(([, value]) => value !== undefined)
			.map(([key, value]) => [key, value === '' ? null : value])
	) as Partial<T>;
}

/** Every primary key in `community_orgs` is a uuid. */
export const orgIdSchema = z.string().uuid('Not a valid organisation id');
export const recordIdSchema = z.string().uuid('Not a valid record id');

/**
 * Audit columns are always set from the session on the server. They are never
 * accepted from a request body — see the note at the top of this file.
 */
export function auditColumns(userId: string | undefined) {
	return {
		last_edited_by: userId ?? null,
		last_edited_at: new Date().toISOString()
	};
}

export function creationColumns(userId: string | undefined) {
	return {
		inserted_by: userId ?? null,
		inserted_at: new Date().toISOString(),
		...auditColumns(userId)
	};
}

export type FieldErrors = Record<string, string[] | undefined>;

/**
 * Every action returns the same shape so `ActionData` is a single object type
 * rather than a union — otherwise a template reading `form?.errors` fails to
 * type-check against the branches that do not carry it.
 */
export function actionFailure(message: string, errors: FieldErrors = {}) {
	return { success: false as const, message, errors };
}

export function actionSuccess() {
	return {
		success: true as const,
		message: undefined,
		errors: undefined as FieldErrors | undefined
	};
}
