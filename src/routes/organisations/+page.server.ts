import { error, fail } from '@sveltejs/kit';
import type { PageServerLoad, Actions } from './$types';
import {
	actionFailure,
	actionSuccess,
	creationColumns,
	organisationSchema
} from '$lib/server/validation';

const PAGE_SIZE = 10;

export const load: PageServerLoad = async ({ locals: { supabase }, url }) => {
	/**
	 * `parseInt` on a non-numeric query string yields NaN, which would reach
	 * PostgREST as `.range(NaN, NaN)`. Clamp to a sensible page instead.
	 */
	const requestedPage = Number(url.searchParams.get('page'));
	const page = Number.isInteger(requestedPage) && requestedPage > 0 ? requestedPage : 1;
	const offset = (page - 1) * PAGE_SIZE;

	/**
	 * Row-level security on `organisations` already limits this to public
	 * organisations plus those the signed-in user holds a role on.
	 */
	const {
		data: organisations,
		count,
		error: loadError
	} = await supabase
		.from('organisations')
		.select(
			`
            org_id,
            entity_name,
            slug,
            description,
            date_established,
            is_public,
            legal_details ( entity_type, abn ),
            contact_info ( phone, email ),
            aliases ( alias, alias_type )
        `,
			{ count: 'exact' }
		)
		.range(offset, offset + PAGE_SIZE - 1)
		.order('entity_name');

	if (loadError) {
		console.error('Failed to load organisations:', loadError);
		error(500, 'Could not load organisations.');
	}

	const totalCount = count ?? 0;

	return {
		organisations,
		totalCount,
		currentPage: page,
		pageSize: PAGE_SIZE,
		totalPages: Math.max(1, Math.ceil(totalCount / PAGE_SIZE))
	};
};

export const actions: Actions = {
	createOrganisation: async ({ request, locals: { supabase, user } }) => {
		const form = Object.fromEntries(await request.formData());
		const parsed = organisationSchema.safeParse(form);

		if (!parsed.success) {
			return fail(
				400,
				actionFailure('Please correct the highlighted fields.', parsed.error.flatten().fieldErrors)
			);
		}

		/**
		 * `organisations.slug` is NOT NULL and unique. The database owns slug
		 * generation, so derive it there rather than racing on a client guess.
		 */
		const { data: slug, error: slugError } = await supabase.rpc('generate_unique_slug', {
			base_slug: parsed.data.entity_name
		});

		if (slugError || !slug) {
			console.error('Failed to generate slug:', slugError);
			return fail(400, actionFailure('Could not create the organisation.'));
		}

		const { error: insertError } = await supabase.from('organisations').insert({
			entity_name: parsed.data.entity_name,
			slug,
			description: parsed.data.description ?? null,
			date_established: parsed.data.date_established ?? null,
			is_public: parsed.data.is_public ?? true,
			...creationColumns(user?.id)
		});

		if (insertError) {
			console.error('Failed to create organisation:', insertError);
			return fail(400, actionFailure('Could not create the organisation.'));
		}

		return actionSuccess();
	}
};
