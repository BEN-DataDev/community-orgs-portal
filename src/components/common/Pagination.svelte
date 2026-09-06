<script lang="ts">
	import { Pagination as SkeletonPagination } from '@skeletonlabs/skeleton-svelte';
	import { ChevronLeft, ChevronRight } from 'lucide-svelte';

	interface Props {
		currentPage: number;
		totalPages: number;
		/** Total number of records, which is what Skeleton's Pagination counts in. */
		totalCount: number;
		pageSize: number;
		baseUrl: string;
	}

	let { currentPage, totalPages, totalCount, pageSize, baseUrl }: Props = $props();

	function hrefFor(page: number): string {
		return `${baseUrl}?page=${page}`;
	}

	let onFirst = $derived(currentPage <= 1);
	let onLast = $derived(currentPage >= totalPages);
</script>

<!--
	Skeleton's Pagination supplies the page range, ellipsis placement and ARIA
	wiring that the previous hand-rolled version approximated. Its Item renders
	an <a> by default, so this stays link-based: pagination works without
	JavaScript, and middle-click / open-in-new-tab behave as expected.

	Prev/Next are plain anchors rather than Skeleton's PrevTrigger/NextTrigger,
	which render <button> and cannot carry an href.
-->
{#if totalPages > 1}
	<SkeletonPagination
		count={totalCount}
		{pageSize}
		page={currentPage}
		class="flex flex-wrap items-center justify-center gap-1"
	>
		{#if onFirst}
			<span class="btn-icon preset-tonal opacity-50" aria-hidden="true">
				<ChevronLeft size={18} />
			</span>
		{:else}
			<a class="btn-icon preset-tonal" href={hrefFor(currentPage - 1)} aria-label="Previous page">
				<ChevronLeft size={18} />
			</a>
		{/if}

		<SkeletonPagination.Context>
			{#snippet children(pagination)}
				{#each pagination().pages as page, index (index)}
					{#if page.type === 'page'}
						<SkeletonPagination.Item
							{...page}
							href={hrefFor(page.value)}
							aria-current={page.value === currentPage ? 'page' : undefined}
							class="btn-icon {page.value === currentPage
								? 'preset-filled-primary-500'
								: 'preset-tonal'}"
						>
							{page.value}
						</SkeletonPagination.Item>
					{:else}
						<SkeletonPagination.Ellipsis {index} class="px-2">&hellip;</SkeletonPagination.Ellipsis>
					{/if}
				{/each}
			{/snippet}
		</SkeletonPagination.Context>

		{#if onLast}
			<span class="btn-icon preset-tonal opacity-50" aria-hidden="true">
				<ChevronRight size={18} />
			</span>
		{:else}
			<a class="btn-icon preset-tonal" href={hrefFor(currentPage + 1)} aria-label="Next page">
				<ChevronRight size={18} />
			</a>
		{/if}
	</SkeletonPagination>
{/if}
