import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ locals: { supabase }, params }) => {
	const { data: contactInfo } = await supabase
		.from('contact_info')
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

	return { contactInfo };
};

export const actions: Actions = {
	updateContact: async ({ request, locals: { supabase } }) => {
		const formData = await request.formData();
		const { orgId, ...contactData } = Object.fromEntries(formData);

		const { data, error } = await supabase
			.from('contact_info')
			.upsert({
				org_id: orgId,
				...contactData
			})
			.select();

		return { success: !error, data };
	}
};
