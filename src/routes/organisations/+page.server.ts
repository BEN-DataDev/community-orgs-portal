import { error, fail } from '@sveltejs/kit';
import type { PageServerLoad, Actions } from './$types';
import {
	actionFailure,
	actionSuccess,
	creationColumns,
	organisationSchema
} from '$lib/server/validation';

const PAGE_SIZE = 10;

interface DirectoryOrganisation {
	org_id: string;
	entity_name: string;
	slug: string;
	description: string | null;
	date_established: string | null;
	is_public: boolean;
	search_rank: number;
	legal_details: Array<{ entity_type: string | null; abn: string | null }>;
	contact_info: Array<{ phone: unknown; email: string | null }>;
	aliases: Array<{ alias: string | null; alias_type: string | null }>;
}

function directoryResult(value: unknown): {
	total: number;
	organisations: DirectoryOrganisation[];
} {
	if (!value || typeof value !== 'object') return { total: 0, organisations: [] };
	const result = value as { total?: unknown; organisations?: unknown };
	return {
		total: typeof result.total === 'number' ? result.total : 0,
		organisations: Array.isArray(result.organisations)
			? (result.organisations as DirectoryOrganisation[])
			: []
	};
}

export const load: PageServerLoad = async ({ locals: { supabase }, url }) => {
	/**
	 * `parseInt` on a non-numeric query string yields NaN, which would reach
	 * PostgREST as `.range(NaN, NaN)`. Clamp to a sensible page instead.
	 */
	const requestedPage = Number(url.searchParams.get('page'));
	const page = Number.isInteger(requestedPage) && requestedPage > 0 ? requestedPage : 1;
	const offset = (page - 1) * PAGE_SIZE;
	const searchQuery = (url.searchParams.get('q') ?? '').trim().slice(0, 100);

	/**
	 * The invoker-rights RPC applies table RLS while matching and returning rows,
	 * preserving organisation and sensitive child-table visibility boundaries.
	 */
	const { data, error: loadError } = await supabase.rpc('search_organisations', {
		p_query: searchQuery,
		p_offset: offset,
		p_limit: PAGE_SIZE
	});

	if (loadError) {
		console.error('Failed to load organisations:', loadError);
		error(500, 'Could not load organisations.');
	}

	const { organisations, total: totalCount } = directoryResult(data);

	return {
		organisations,
		totalCount,
		currentPage: page,
		pageSize: PAGE_SIZE,
		totalPages: Math.max(1, Math.ceil(totalCount / PAGE_SIZE)),
		searchQuery
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
