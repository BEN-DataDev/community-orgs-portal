import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals: { supabase }, params }) => {
	const { data: operationalInfo } = await supabase
		.from('operational_details')
		.select(
			`
            *,
            organisations (
                legal_name,
                trading_name
            ),
            locations (
                id,
                name,
                address,
                type
            ),
            staff_count,
            volunteer_count,
            operational_hours,
            service_areas
        `
		)
		.eq('org_id', params.id)
		.single();

	return { operationalInfo };
};

export const actions: Actions = {
	updateOperations: async ({ request, locals: { supabase } }) => {
		const formData = await request.formData();
		const { orgId, ...operationsData } = Object.fromEntries(formData);

		const { data, error } = await supabase
			.from('operational_details')
			.upsert({
				org_id: orgId,
				...operationsData
			})
			.select();

		return { success: !error, data };
	}
};
