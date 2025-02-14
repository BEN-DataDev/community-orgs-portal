import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ locals: { supabase }, params }) => {
	const [relationships, organisation] = await Promise.all([
		supabase
			.from('relationships')
			.select(
				`
                *,
                partner_details:organisations!partner_org_id (
                    legal_name,
                    trading_name
                )
            `
			)
			.eq('org_id', params.id)
			.order('start_date', { ascending: false }),
		supabase
			.from('organisations')
			.select('legal_name, trading_name')
			.eq('org_id', params.id)
			.single()
	]);

	return {
		relationships: relationships.data,
		organisation: organisation.data
	};
};

export const actions: Actions = {
	createRelationship: async ({ request, locals: { supabase } }) => {
		const formData = await request.formData();
		const relationshipData = Object.fromEntries(formData);

		const { data, error } = await supabase.from('relationships').insert(relationshipData).select();

		return { success: !error, data };
	}
};
