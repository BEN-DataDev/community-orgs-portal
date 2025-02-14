<script lang="ts">
	import { onMount } from 'svelte';
	import * as d3 from 'd3';

	interface Props {
		relationships: Array<{
			start_date: string;
			end_date: string | null;
			relationship_type: string;
			partner_details: {
				legal_name: string;
			};
		}>;
	}

	let { relationships }: Props = $props();

	let container: HTMLDivElement;

	onMount(() => {
		const margin = { top: 20, right: 20, bottom: 30, left: 200 };
		const width = container.clientWidth - margin.left - margin.right;
		const height = relationships.length * 40;

		const svg = d3
			.select(container)
			.append('svg')
			.attr('width', width + margin.left + margin.right)
			.attr('height', height + margin.top + margin.bottom)
			.append('g')
			.attr('transform', `translate(${margin.left},${margin.top})`);

		const timeExtent = d3.extent([
			...relationships.map((d) => new Date(d.start_date)),
			...relationships.map((d) => (d.end_date ? new Date(d.end_date) : new Date()))
		]) as [Date, Date];

		const xScale = d3.scaleTime().domain(timeExtent).range([0, width]);

		const yScale = d3
			.scaleBand()
			.domain(relationships.map((d) => d.partner_details.legal_name))
			.range([0, height])
			.padding(0.1);

		// Draw axes
		svg.append('g').attr('transform', `translate(0,${height})`).call(d3.axisBottom(xScale));

		svg.append('g').call(d3.axisLeft(yScale));

		// Draw relationship bars
		svg
			.selectAll('rect')
			.data(relationships)
			.enter()
			.append('rect')
			.attr('y', (d) => yScale(d.partner_details.legal_name) ?? 0)
			.attr('x', (d) => xScale(new Date(d.start_date)))
			.attr('width', (d) => {
				const end = d.end_date ? new Date(d.end_date) : new Date();
				return xScale(end) - xScale(new Date(d.start_date));
			})
			.attr('height', yScale.bandwidth())
			.attr('fill', (d) => getRelationshipColor(d.relationship_type))
			.append('title')
			.text((d) => `${d.relationship_type}\n${d.partner_details.legal_name}`);
	});

	function getRelationshipColor(type: string): string {
		const colors: { [key: string]: string } = {
			Partnership: '#4C51BF',
			Funding: '#38A169',
			'Service Provider': '#ED8936',
			'Network Member': '#667EEA',
			Collaboration: '#9F7AEA',
			'Strategic Alliance': '#ED64A6'
		};
		return colors[type] || '#718096';
	}
</script>

<div bind:this={container} class="h-full min-h-[400px] w-full"></div>

<style>
	:global(svg) {
		max-width: 100%;
		height: auto;
	}
</style>
