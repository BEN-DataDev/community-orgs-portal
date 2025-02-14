import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ locals: {supabase}, url }) => {
	const searchParams = url.searchParams;
	const page = parseInt(searchParams.get('page') || '1');
	const limit = 10;
	const offset = (page - 1) * limit;

	const { data: organisations, count } = await supabase
		.from('organisations')
		.select(
			`
            *,
            legal_details (
                entity_type,
                abn
            ),
            contact_info (
                phone,
                email
            )
        `,
			{ count: 'exact' }
		)
		.range(offset, offset + limit - 1)
		.order('legal_name');

	return {
		organisations,
		totalCount: count || 0,
		currentPage: page,
		totalPages: Math.ceil((count || 0) / limit)
	};
};

export const actions: Actions = {
	createOrganisation: async ({ request, locals: { supabase } }) => {
		const formData = await request.formData();
		const { legalName, tradingName, dateEstablished } = Object.fromEntries(formData);

		const { data, error } = await supabase
			.from('organisations')
			.insert({
				legal_name: legalName,
				trading_name: tradingName,
				date_established: dateEstablished
			})
			.select();

		return { success: !error, data, error };
	}
};
