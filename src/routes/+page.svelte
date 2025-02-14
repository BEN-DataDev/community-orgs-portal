<script lang="ts">
	import { goto } from '$app/navigation';
	const features = [
		{
			title: 'Contact Management',
			description: "Keep track of all your organisation's contact information in one place."
		},
		{
			title: 'Financial Tracking',
			description: 'Monitor financial information and funding sources efficiently.'
		},
		{
			title: 'Legal Compliance',
			description: 'Stay on top of legal requirements and documentation.'
		},
		{
			title: 'Operations Overview',
			description: 'Manage locations, staff, and service areas effectively.'
		}
	];
</script>

<div class="min-h-screen bg-gradient-to-b from-blue-50 to-white">
	<div class="container mx-auto px-4 py-16">
		<header class="text-center">
			<h1 class="mb-6 text-5xl font-bold text-blue-900">Organisation Management Platform</h1>
			<p class="mx-auto mb-8 max-w-2xl text-xl text-gray-600">
				Track relationships, manage contacts, and monitor financial data for your organisation
				network
			</p>
			<button class="variant-filled-primary btn text-lg" onclick={() => goto('/dashboard')}>
				Get Started
			</button>
		</header>

		<div class="mt-24 grid grid-cols-1 gap-12 md:grid-cols-3">
			<div class="rounded-lg bg-white p-8 shadow-lg">
				<h2 class="mb-4 text-2xl font-bold text-blue-900">Relationship Management</h2>
				<p class="text-gray-600">
					Track partnerships, collaborations, and network connections with detailed timelines and
					insights
				</p>
			</div>

			<div class="rounded-lg bg-white p-8 shadow-lg">
				<h2 class="mb-4 text-2xl font-bold text-blue-900">Contact Information</h2>
				<p class="text-gray-600">
					Keep your organisation's contact details up-to-date and easily accessible
				</p>
			</div>

			<div class="rounded-lg bg-white p-8 shadow-lg">
				<h2 class="mb-4 text-2xl font-bold text-blue-900">Financial Tracking</h2>
				<p class="text-gray-600">
					Monitor revenue, funding sources, and maintain crucial financial documentation
				</p>
			</div>
		</div>

		<div class="mt-24 text-center">
			<h2 class="mb-8 text-3xl font-bold text-blue-900">Ready to streamline your organisation?</h2>
			<button class="variant-filled-primary btn text-lg" onclick={() => goto('/dashboard')}>
				Start Now
			</button>
		</div>
	</div>
</div>
