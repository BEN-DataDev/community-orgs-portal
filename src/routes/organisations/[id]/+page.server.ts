import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ locals: { supabase }, params }) => {
	const [organisation, relationships] = await Promise.all([
		supabase
			.from('organisations')
			.select(
				`
                *,
                legal_details (*),
                contact_info (*),
                operational_details (*),
                financial_info (*),
                governance (*),
                programs_services (*),
                accreditation (*),
                resources_assets (*)
            `
			)
			.eq('org_id', params.id)
			.single(),
		supabase.from('relationships').select('*').eq('org_id', params.id)
	]);

	return {
		organisation: organisation.data,
		relationships: relationships.data
	};
};

export const actions: Actions = {
	updateOrganisation: async ({ request, locals: { supabase } }) => {
		const formData = await request.formData();
		const { orgId, ...updateData } = Object.fromEntries(formData);

		const { data, error } = await supabase
			.from('organisations')
			.update(updateData)
			.eq('org_id', orgId)
			.select();

		return { success: !error, data, error };
	}
};
