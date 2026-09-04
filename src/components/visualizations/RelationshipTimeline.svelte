<script lang="ts">
	import * as d3 from 'd3';

	interface Props {
		relationships: Array<{
			relationship_id: string;
			start_date: string | null;
			end_date: string | null;
			relationship_type: string | null;
			partner_org: string | null;
		}>;
	}

	let { relationships }: Props = $props();

	let container = $state<HTMLDivElement | null>(null);
	let width = $state(0);

	/** Only rows with a start date and a partner can be placed on the timeline. */
	let plottable = $derived(
		relationships.filter((r) => r.start_date !== null && r.partner_org !== null)
	);

	$effect(() => {
		if (!container) return;
		const observer = new ResizeObserver((entries) => {
			width = entries[0]?.contentRect.width ?? 0;
		});
		observer.observe(container);
		return () => observer.disconnect();
	});

	/**
	 * Redraws whenever the data or the measured width changes. The previous
	 * chart is removed first, so this does not accumulate SVG elements.
	 */
	$effect(() => {
		if (!container || width <= 0) return;

		const margin = { top: 20, right: 20, bottom: 30, left: 200 };
		const innerWidth = Math.max(1, width - margin.left - margin.right);
		const innerHeight = Math.max(1, plottable.length * 40);

		d3.select(container).selectAll('svg').remove();
		if (plottable.length === 0) return;

		const svg = d3
			.select(container)
			.append('svg')
			.attr('width', innerWidth + margin.left + margin.right)
			.attr('height', innerHeight + margin.top + margin.bottom)
			.append('g')
			.attr('transform', `translate(${margin.left},${margin.top})`);

		const start = (d: (typeof plottable)[number]) => new Date(d.start_date as string);
		const end = (d: (typeof plottable)[number]) => (d.end_date ? new Date(d.end_date) : new Date());

		const timeExtent = d3.extent([...plottable.map(start), ...plottable.map(end)]) as [Date, Date];

		const xScale = d3.scaleTime().domain(timeExtent).range([0, innerWidth]);
		const yScale = d3
			.scaleBand()
			.domain(plottable.map((d) => d.partner_org as string))
			.range([0, innerHeight])
			.padding(0.1);

		svg.append('g').attr('transform', `translate(0,${innerHeight})`).call(d3.axisBottom(xScale));
		svg.append('g').call(d3.axisLeft(yScale));

		svg
			.selectAll('rect')
			.data(plottable)
			.enter()
			.append('rect')
			.attr('y', (d) => yScale(d.partner_org as string) ?? 0)
			.attr('x', (d) => xScale(start(d)))
			.attr('width', (d) => Math.max(1, xScale(end(d)) - xScale(start(d))))
			.attr('height', yScale.bandwidth())
			.attr('fill', (d) => getRelationshipColor(d.relationship_type))
			.append('title')
			.text((d) => `${d.relationship_type ?? 'Relationship'}\n${d.partner_org}`);
	});

	function getRelationshipColor(type: string | null): string {
		const colors: { [key: string]: string } = {
			Partnership: '#4C51BF',
			Funding: '#38A169',
			'Service Provider': '#ED8936',
			'Network Member': '#667EEA',
			Collaboration: '#9F7AEA',
			'Strategic Alliance': '#ED64A6'
		};
		return (type && colors[type]) || '#718096';
	}
</script>

<div bind:this={container} class="h-full min-h-[400px] w-full">
	{#if plottable.length === 0}
		<p class="text-gray-600">No dated relationships to plot yet.</p>
	{/if}
</div>

<style>
	:global(svg) {
		max-width: 100%;
		height: auto;
	}
</style>
