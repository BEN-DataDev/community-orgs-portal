<script lang="ts">
    interface Props {
        currentPage: number;
        totalPages: number;
        baseUrl: string;
    }

    let { currentPage, totalPages, baseUrl }: Props = $props();

    let pages = $derived(Array.from({ length: totalPages }, (_, i) => i + 1));
    let visiblePages = $derived(pages.filter(page => 
        page === 1 || 
        page === totalPages || 
        (page >= currentPage - 1 && page <= currentPage + 1)
    ));
</script>

<nav class="flex justify-center space-x-2">
    {#each visiblePages as page}
        {#if page === visiblePages[0] && page > 1}
            <span class="px-3 py-2">...</span>
        {/if}
        
        <a
            href="{baseUrl}?page={page}"
            class="px-3 py-2 rounded-md {page === currentPage 
                ? 'bg-indigo-600 text-white' 
                : 'text-gray-700 hover:bg-gray-50'}"
        >
            {page}
        </a>

        {#if page === visiblePages[visiblePages.length - 1] && page < totalPages}
            <span class="px-3 py-2">...</span>
        {/if}
    {/each}
</nav>