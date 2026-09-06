<script lang="ts">
	import { resolve } from '$app/paths';
	const features = [
		{
			title: 'Relationship Management',
			body: 'Track partnerships, collaborations, and network connections with detailed timelines and insights'
		},
		{
			title: 'Contact Information',
			body: "Keep your organisation's contact details up-to-date and easily accessible"
		},
		{
			title: 'Financial Tracking',
			body: 'Monitor revenue, funding sources, and maintain crucial financial documentation'
		}
	];
</script>

<div class="py-8 sm:py-12 lg:py-16">
	<header class="text-center">
		<h1 class="mb-6 text-3xl font-bold sm:text-4xl lg:text-5xl">
			Organisation Management Platform
		</h1>
		<p class="text-surface-700-300 mx-auto mb-8 max-w-2xl text-base sm:text-lg lg:text-xl">
			Track relationships, manage contacts, and monitor financial data for your organisation network
		</p>
		<a class="btn preset-filled-primary-500 sm:btn-lg" href={resolve('/organisations')}
			>Get Started</a
		>
	</header>

	<div class="mt-16 grid grid-cols-1 gap-6 sm:mt-20 md:grid-cols-3 md:gap-8 lg:gap-12">
		{#each features as feature (feature.title)}
			<div class="card preset-tonal p-6 lg:p-8">
				<h2 class="mb-3 text-xl font-bold lg:text-2xl">{feature.title}</h2>
				<p class="text-surface-700-300">{feature.body}</p>
			</div>
		{/each}
	</div>

	<div class="mt-16 text-center sm:mt-20">
		<h2 class="mb-6 text-2xl font-bold sm:text-3xl">Ready to streamline your organisation?</h2>
		<a class="btn preset-filled-primary-500 sm:btn-lg" href={resolve('/organisations')}>Start Now</a
		>
	</div>
</div>
