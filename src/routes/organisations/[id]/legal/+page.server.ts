import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ locals: { supabase }, params }) => {
	const { data: legalInfo } = await supabase
		.from('legal_details')
		.select(
			`
            *,
            organisations (
                legal_name,
                trading_name
            )
        `
		)
		.eq('org_id', params.id)
		.single();

	return { legalInfo };
};

export const actions: Actions = {
	updateLegal: async ({ request, locals: { supabase } }) => {
		const formData = await request.formData();
		const { orgId, ...legalData } = Object.fromEntries(formData);

		const { data, error } = await supabase
			.from('legal_details')
			.upsert({
				org_id: orgId,
				...legalData
			})
			.select();

		return { success: !error, data };
	}
};
