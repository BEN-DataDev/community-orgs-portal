import { error, fail } from '@sveltejs/kit';
import { z } from 'zod';
import { isSiteAdmin } from '$lib/server/authorization';
import type { Actions, PageServerLoad } from './$types';

const history = z.object({
	configuration_revision: z.number(),
	current_scope_revision_id: z.string().nullable(),
	revisions: z.array(
		z.object({
			id: z.string(),
			revision: z.string(),
			postcodes: z.array(z.string().regex(/^[0-9]{4}$/)),
			inclusion_policy_version: z.string(),
			impact_assessment: z.string(),
			requires_rebaseline: z.boolean(),
			effective_at: z.string(),
			approved_at: z.string(),
			approved_by: z.string().uuid().nullable(),
			reason: z.string(),
			current: z.boolean()
		})
	)
});

async function loadHistory(locals: App.Locals) {
	const result = await locals.providers.database.rpc('portal_scope_history');
	if (result.error)
		error(result.error.code === '42501' ? 403 : 500, 'Could not load portal scope.');
	const parsed = history.safeParse(result.data);
	if (!parsed.success) error(500, 'Unexpected portal scope response.');
	return parsed.data;
}

export const load: PageServerLoad = async ({ locals, setHeaders }) => {
	setHeaders({ 'cache-control': 'private, no-store' });
	if (!(await isSiteAdmin(locals.providers.database, locals.user?.id)))
		error(403, 'Administrator required.');
	return loadHistory(locals);
};

export const actions: Actions = {
	default: async ({ locals, request }) => {
		if (!(await isSiteAdmin(locals.providers.database, locals.user?.id)))
			error(403, 'Administrator required.');
		const formData = Object.fromEntries(await request.formData());
		const postcodes = String(formData.postcodes ?? '')
			.split(/[\s,]+/)
			.filter(Boolean);
		const canonical = [...new Set(postcodes)].sort();
		const input = z
			.object({
				inclusionPolicyVersion: z.string().trim().min(1).max(200),
				reason: z.string().trim().min(1).max(2000),
				impactAssessment: z.string().trim().min(1).max(4000),
				expectedRevision: z.coerce.number().int().positive()
			})
			.safeParse(formData);
		if (
			!input.success ||
			canonical.length < 1 ||
			canonical.length > 500 ||
			canonical.length !== postcodes.length ||
			canonical.some((postcode) => !/^[0-9]{4}$/.test(postcode))
		) {
			return fail(400, {
				message:
					'Enter 1 to 500 unique four-digit postcodes plus policy, impact and approval reasons.'
			});
		}
		const result = await locals.providers.database.rpc('configure_portal_scope', {
			p_postcodes: canonical,
			p_inclusion_policy_version: input.data.inclusionPolicyVersion,
			p_reason: input.data.reason,
			p_impact_assessment: input.data.impactAssessment,
			p_requires_rebaseline: formData.requiresRebaseline === 'on',
			p_expected_revision: input.data.expectedRevision
		});
		if (result.error)
			return fail(result.error.code === '42501' ? 403 : result.error.code === '40001' ? 409 : 400, {
				message:
					result.error.code === '40001'
						? 'Portal configuration changed. Reload before creating a revision.'
						: 'Scope revision was not created. Check the postcode set and approval details.'
			});
		return {
			message: `Scope revision created with ID ${result.data}. Reconfigure source acquisitions before running them.`
		};
	}
};
