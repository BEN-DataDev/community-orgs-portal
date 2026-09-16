<script lang="ts">
	import {
		factGroup,
		factValue,
		observationDate,
		safePublicUrl,
		type RegisterFact,
		type RegisterSection
	} from '../../lib/register-facts';
	let { facts, section }: { facts: RegisterFact[]; section: RegisterSection } = $props();
	const selected = $derived(facts.filter((fact) => fact.section === section));
	const groups = $derived([...new Set(selected.map((fact) => factGroup(fact.field)))]);
</script>

<section
	aria-label={`${section} register details`}
	class="card preset-outlined-surface-200-800 mt-6 space-y-4 p-4"
>
	<h2 class="text-lg font-semibold">
		{section === 'Governance' ? 'Governance summary' : 'Published register observations'}
	</h2>
	{#if selected.length}
		<p class="text-sm">
			Approved observations are shown separately for each source. Observation dates describe
			retrieval, not independent verification or confirmation by the organisation. Unlisted facts
			are not published; absence does not mean No.
		</p>
		{#if section === 'Contact'}<p class="text-sm">
				The administrative address is the register’s contact address. It is not necessarily a
				service location.
			</p>{/if}
		{#if section === 'Operations'}<p class="text-sm">
				Operating jurisdictions do not imply service availability everywhere. Yes and No reflect
				explicit register flags; unlisted flags are unknown or not published.
			</p>{/if}
		{#if section === 'Finance'}<p class="text-sm">
				Financial year end is a reporting calendar, not a financial result or reporting-period
				observation.
			</p>{/if}
		{#if section === 'Governance'}<p class="text-sm">
				A reported count does not identify responsible people or describe board composition.
			</p>{/if}
		{#each groups as group (group)}
			<div class="space-y-3">
				<h3 class="font-semibold">{group}</h3>
				<dl class="divide-surface-200-800 divide-y">
					{#each selected.filter((fact) => factGroup(fact.field) === group) as fact (fact)}
						<div class="py-3" data-register-field={fact.field}>
							<dt class="font-medium">{fact.label}</dt>
							<dd class="mt-1 space-y-2">
								{#if fact.field === 'website' && typeof fact.value === 'string' && safePublicUrl(fact.value)}
									<a
										class="anchor break-all"
										href={safePublicUrl(fact.value)!}
										rel="noopener noreferrer">{fact.value}</a
									>
								{:else}<p class="break-words whitespace-pre-wrap">{factValue(fact)}</p>{/if}
								{#if fact.effective_date}<p class="text-sm">
										Source-reported date: <time datetime={fact.effective_date}
											>{fact.effective_date}</time
										>
									</p>{/if}
								{#if fact.retained_address_components.length}<p class="text-sm">
										Previously approved address components retained where this observation omitted
										them.
									</p>{/if}
								<p class="text-sm">
									Source: {#if fact.source_url}<a
											class="anchor"
											href={fact.source_url}
											rel="noopener noreferrer">{fact.source_title}</a
										>{:else}{fact.source_title}{/if}
								</p>
								<p class="text-sm">
									Observed <time datetime={fact.observed_at}
										>{observationDate(fact.observed_at)}</time
									>
									· Published
									<time datetime={fact.published_at}>{observationDate(fact.published_at)}</time>
								</p>
								{#if !fact.unchanged_since_import}<p class="text-sm">
										The portal value has changed since this publication; this is the approved source
										observation.
									</p>{/if}
								{#if fact.licence}<p class="text-sm">
										Licence: {#if fact.licence_url}<a
												class="anchor"
												href={fact.licence_url}
												rel="noopener noreferrer">{fact.licence}</a
											>{:else}{fact.licence}{/if}
									</p>{/if}
							</dd>
						</div>
					{/each}
				</dl>
			</div>
		{/each}
	{:else}<p class="text-surface-600-400">
			No approved register facts are published for this section.
		</p>{/if}
</section>
