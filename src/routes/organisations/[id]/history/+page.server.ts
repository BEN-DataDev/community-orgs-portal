import type { PageServerLoad, Actions } from './$types';

export const load: PageServerLoad = async ({ locals: { supabase }, params }) => {
	const [historicalInfo, organisation] = await Promise.all([
		supabase
			.from('historical_info')
			.select(
				`
        *,
        inserted_by(name, email),
        last_edited_by(name, email)
      `
			)
			.eq('org_id', params.id)
			.order('milestone_date', { ascending: false }),
		supabase
			.from('organisations')
			.select('legal_name, trading_name')
			.eq('org_id', params.id)
			.single()
	]);

	if (historicalInfo.error) throw new Error(historicalInfo.error.message);
	if (organisation.error) throw new Error(organisation.error.message);

	return {
		historicalInfo: historicalInfo.data,
		organisation: organisation.data
	};
};

export const actions: Actions = {
	updateHistory: async ({ request, locals: { supabase } }) => {
		const formData = await request.formData();
		const orgId = formData.get('orgId')?.toString();
		const foundingMembers = formData.get('foundingMembers')?.toString() || '';
		const milestoneDate = formData.get('milestoneDate')?.toString();
		const milestoneDescription = formData.get('milestoneDescription')?.toString();
		const structuralChanges = formData.get('structuralChanges')?.toString() || '[]';

		const { data, error } = await supabase
			.from('historical_info')
			.upsert({
				org_id: orgId,
				founding_members: foundingMembers.split(',').map((m: string) => m.trim()),
				milestone_date: milestoneDate,
				milestone_description: milestoneDescription,
				structural_changes: JSON.parse(structuralChanges),
				last_edited_at: new Date().toISOString()
			})
			.select();

		return { success: !error, data };
	}
};
