import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ locals: { supabase }, params }) => {
	const { data: financialInfo } = await supabase
		.from('financial_info')
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

	return { financialInfo };
};

export const actions: Actions = {
	updateFinancial: async ({ request, locals: { supabase } }) => {
		const formData = await request.formData();
		const { orgId, ...financialData } = Object.fromEntries(formData);

		const { data, error } = await supabase
			.from('financial_info')
			.upsert({
				org_id: orgId,
				...financialData
			})
			.select();

		return { success: !error, data };
	}
};
