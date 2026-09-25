import type { SupabaseClient } from '@supabase/supabase-js';
import type { SafeSession } from '$lib/auth/session';
import type { Database } from '$lib/db.types';
import type { TypedSupabaseClient } from '$lib/supabase-client';
import type {
	AvatarProfile,
	AvatarProfileUpdate,
	AvatarProvider,
	DomainDatabase,
	DomainFunctionArgs,
	DomainFunctionName,
	DomainFunctionResult,
	IdentityProvider,
	MaintenanceProvider,
	MaintenanceResult,
	ProviderDescriptor,
	ProviderFailure,
	ProviderResult,
	RequestProviders
} from './contracts';

const AVATAR_BUCKET = 'avatars';

export const SUPABASE_PROVIDER: ProviderDescriptor = {
	id: 'supabase',
	production: true,
	capabilities: {
		postgresql: 'supported',
		verified_identity: 'supported',
		private_storage: 'supported',
		scheduler: 'external',
		secret_references: 'external',
		backup_restore: 'external',
		migrations: 'supported'
	}
};

function failure(error: unknown): ProviderFailure | null {
	if (!error) return null;
	if (typeof error === 'object' && error !== null) {
		const value = error as { message?: unknown; code?: unknown; status?: unknown };
		return {
			message: typeof value.message === 'string' ? value.message : 'Provider operation failed.',
			...(typeof value.code === 'string' ? { code: value.code } : {}),
			...(typeof value.status === 'number' ? { status: value.status } : {})
		};
	}
	return { message: 'Provider operation failed.' };
}

export class SupabaseDomainDatabase implements DomainDatabase {
	constructor(private readonly client: TypedSupabaseClient) {}

	async rpc<Name extends DomainFunctionName>(
		name: Name,
		args?: DomainFunctionArgs<Name>
	): Promise<ProviderResult<DomainFunctionResult<Name>>> {
		// The generated function map is the public contract. The cast is isolated
		// here because supabase-js cannot correlate a generic name with its args.
		const result = await this.client.rpc(name, args as never);
		return {
			data: result.data as DomainFunctionResult<Name> | null,
			error: failure(result.error)
		};
	}
}

export class SupabaseIdentityProvider implements IdentityProvider {
	constructor(private readonly client: TypedSupabaseClient) {}

	async verifyRequest(): Promise<SafeSession> {
		const {
			data: { session }
		} = await this.client.auth.getSession();
		if (!session) return { session: null, user: null, aal: null, isAnonymous: false };

		const {
			data: { user },
			error
		} = await this.client.auth.getUser();
		if (error || !user) return { session: null, user: null, aal: null, isAnonymous: false };

		const { data: aal } = await this.client.auth.mfa.getAuthenticatorAssuranceLevel();
		return {
			session: { ...session, user },
			user,
			aal: aal ? { currentLevel: aal.currentLevel, nextLevel: aal.nextLevel } : null,
			isAnonymous: user.is_anonymous === true
		};
	}
}

export class SupabaseAvatarProvider implements AvatarProvider {
	constructor(private readonly client: TypedSupabaseClient) {}

	async readProfile(userId: string): Promise<ProviderResult<AvatarProfile>> {
		const result = await this.client
			.schema('public')
			.from('users')
			.select('avatar_path, avatar_source, avatar_revision, avatar_url')
			.eq('id', userId)
			.maybeSingle();
		return { data: result.data as AvatarProfile | null, error: failure(result.error) };
	}

	async compareAndSwapProfile(
		userId: string,
		revision: number,
		update: AvatarProfileUpdate
	): Promise<ProviderResult<{ id: string }>> {
		const result = await this.client
			.schema('public')
			.from('users')
			.update(update)
			.eq('id', userId)
			.eq('avatar_revision', revision)
			.select('id')
			.maybeSingle();
		return { data: result.data, error: failure(result.error) };
	}

	async upload(path: string, bytes: Uint8Array): Promise<ProviderResult<null>> {
		const result = await this.client.storage.from(AVATAR_BUCKET).upload(path, bytes, {
			contentType: 'image/webp',
			upsert: false,
			cacheControl: '300'
		});
		return { data: null, error: failure(result.error) };
	}

	async remove(paths: string[]): Promise<ProviderResult<null>> {
		const result = await this.client.storage.from(AVATAR_BUCKET).remove(paths);
		return { data: null, error: failure(result.error) };
	}

	async signedUrl(path: string, expiresInSeconds: number) {
		const result = await this.client.storage
			.from(AVATAR_BUCKET)
			.createSignedUrl(path, expiresInSeconds);
		return { data: result.data, error: failure(result.error) };
	}
}

export function supabaseRequestProviders(client: TypedSupabaseClient): RequestProviders {
	return {
		descriptor: SUPABASE_PROVIDER,
		database: new SupabaseDomainDatabase(client),
		identity: new SupabaseIdentityProvider(client),
		avatars: new SupabaseAvatarProvider(client)
	};
}

export class SupabaseMaintenanceProvider implements MaintenanceProvider {
	constructor(private readonly client: SupabaseClient<Database>) {}

	async run(): Promise<MaintenanceResult> {
		const health = await this.client.rpc('health_check');
		if (health.error) throw new ProviderMaintenanceError('health_check', failure(health.error)!);

		const domain = this.client.schema('community_orgs');
		const purged = await domain.rpc('purge_stale_anonymous_users');
		if (purged.error) throw new ProviderMaintenanceError('guest_cleanup', failure(purged.error)!);

		const abandoned = await domain.rpc('abandoned_account_avatars');
		if (abandoned.error)
			throw new ProviderMaintenanceError('avatar_cleanup', failure(abandoned.error)!);
		const paths = (abandoned.data ?? []).map((row: { path: string }) => row.path);
		if (paths.length) {
			const removed = await this.client.storage.from(AVATAR_BUCKET).remove(paths);
			if (removed.error)
				throw new ProviderMaintenanceError('avatar_cleanup', failure(removed.error)!);
		}

		const acquisitions = await domain.rpc('enqueue_due_acquisitions');
		if (acquisitions.error)
			throw new ProviderMaintenanceError('acquisition_queue', failure(acquisitions.error)!);

		return {
			health: health.data,
			purgedAnonymousUsers: purged.data ?? 0,
			abandonedAvatarPaths: paths,
			acquisitions: acquisitions.data
		};
	}
}

export class ProviderMaintenanceError extends Error {
	constructor(
		readonly stage: 'health_check' | 'guest_cleanup' | 'avatar_cleanup' | 'acquisition_queue',
		readonly failure: ProviderFailure
	) {
		super(failure.message);
		this.name = 'ProviderMaintenanceError';
	}
}
