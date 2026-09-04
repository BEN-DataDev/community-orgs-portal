import { error, fail } from '@sveltejs/kit';
import type { PageServerLoad, Actions } from './$types';
import { requireOrgAccess, requireOrgEditor } from '$lib/server/authorization';
import {
	actionFailure,
	actionSuccess,
	auditColumns,
	creationColumns,
	documentSchema,
	legalSchema,
	orgIdSchema,
	recordIdSchema,
	toColumns
} from '$lib/server/validation';

export const load: PageServerLoad = async ({ locals: { supabase, user }, params }) => {
	const orgId = orgIdSchema.safeParse(params.id);
	if (!orgId.success) {
		error(404, 'Organisation not found.');
	}

	const { data: organisation, error: organisationError } = await supabase
		.from('organisations')
		.select('org_id, entity_name, slug, is_public')
		.eq('org_id', orgId.data)
		.maybeSingle();

	if (organisationError) {
		console.error('Failed to load organisation:', organisationError);
		error(500, 'Could not load this organisation.');
	}

	if (!organisation) {
		error(404, 'Organisation not found.');
	}

	const roleLevel = await requireOrgAccess(supabase, user?.id, orgId.data, organisation.is_public);

	const [legal, documents] = await Promise.all([
		supabase.from('legal_details').select('*').eq('org_id', orgId.data).maybeSingle(),
		supabase
			.from('documents')
			.select('*')
			.eq('org_id', orgId.data)
			.order('name', { ascending: true })
	]);

	if (legal.error) {
		console.error('Failed to load legal details:', legal.error);
		error(500, 'Could not load the legal details.');
	}

	if (documents.error) {
		console.error('Failed to load documents:', documents.error);
		error(500, 'Could not load the documents.');
	}

	return {
		organisation,
		roleLevel,
		legalInfo: legal.data,
		documents: documents.data ?? []
	};
};

export const actions: Actions = {
	updateLegal: async ({ request, locals: { supabase, user }, params }) => {
		const orgId = orgIdSchema.safeParse(params.id);
		if (!orgId.success) {
			return fail(400, actionFailure('Not a valid organisation id.'));
		}
		await requireOrgEditor(supabase, user?.id, orgId.data);

		const form = Object.fromEntries(await request.formData());
		const parsed = legalSchema.safeParse(form);

		if (!parsed.success) {
			return fail(
				400,
				actionFailure('Please correct the highlighted fields.', parsed.error.flatten().fieldErrors)
			);
		}

		/**
		 * `onConflict` is required here. This table is keyed on `legal_id`,
		 * which the payload does not carry, so without it every save would
		 * insert a new row instead of updating the existing one.
		 */
		const { error: saveError } = await supabase.from('legal_details').upsert(
			{
				org_id: orgId.data,
				...toColumns(parsed.data),
				...auditColumns(user?.id)
			},
			{ onConflict: 'org_id' }
		);

		if (saveError) {
			console.error('Failed to save legal details:', saveError);
			return fail(400, actionFailure('Could not save your changes.'));
		}

		return actionSuccess();
	},

	addDocument: async ({ request, locals: { supabase, user }, params }) => {
		const orgId = orgIdSchema.safeParse(params.id);
		if (!orgId.success) {
			return fail(400, actionFailure('Not a valid organisation id.'));
		}
		await requireOrgEditor(supabase, user?.id, orgId.data);

		const form = Object.fromEntries(await request.formData());
		const parsed = documentSchema.safeParse(form);

		if (!parsed.success) {
			return fail(
				400,
				actionFailure('Please correct the highlighted fields.', parsed.error.flatten().fieldErrors)
			);
		}

		const { error: insertError } = await supabase.from('documents').insert({
			org_id: orgId.data,
			name: parsed.data.name,
			url: parsed.data.url,
			category: parsed.data.category ?? 'legal',
			...creationColumns(user?.id)
		});

		if (insertError) {
			console.error('Failed to add document:', insertError);
			return fail(400, actionFailure('Could not add that document.'));
		}

		return actionSuccess();
	},

	deleteDocument: async ({ request, locals: { supabase, user }, params }) => {
		const orgId = orgIdSchema.safeParse(params.id);
		if (!orgId.success) {
			return fail(400, actionFailure('Not a valid organisation id.'));
		}
		await requireOrgEditor(supabase, user?.id, orgId.data);

		const documentId = recordIdSchema.safeParse((await request.formData()).get('document_id'));
		if (!documentId.success) {
			return fail(400, actionFailure('Not a valid document id.'));
		}

		/**
		 * Scoped by `org_id` as well as the primary key, so a document id from
		 * another organisation cannot be deleted through this action.
		 */
		const { error: deleteError } = await supabase
			.from('documents')
			.delete()
			.eq('document_id', documentId.data)
			.eq('org_id', orgId.data);

		if (deleteError) {
			console.error('Failed to delete document:', deleteError);
			return fail(400, actionFailure('Could not remove that document.'));
		}

		return actionSuccess();
	}
};
