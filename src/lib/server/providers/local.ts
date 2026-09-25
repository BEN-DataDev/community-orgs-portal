import type {
	AvatarProfile,
	AvatarProfileUpdate,
	AvatarProvider,
	ProviderDescriptor,
	ProviderResult
} from './contracts';

/**
 * Deliberately limited local proof adapter. It exercises the private-storage
 * and optimistic-update contracts without pretending to supply production
 * identity, scheduling, secrets or backups.
 */
export const LOCAL_PROVIDER: ProviderDescriptor = {
	id: 'local-postgres',
	production: false,
	capabilities: {
		postgresql: 'supported',
		verified_identity: 'unsupported',
		private_storage: 'supported',
		scheduler: 'external',
		secret_references: 'unsupported',
		backup_restore: 'external',
		migrations: 'supported'
	}
};

const ok = <Value>(data: Value): ProviderResult<Value> => ({ data, error: null });

export class LocalAvatarProvider implements AvatarProvider {
	readonly profiles = new Map<string, AvatarProfile>();
	readonly objects = new Map<string, Uint8Array>();

	async readProfile(userId: string): Promise<ProviderResult<AvatarProfile>> {
		return ok(
			this.profiles.get(userId) ?? {
				avatar_path: null,
				avatar_source: 'initials',
				avatar_revision: 0,
				avatar_url: null
			}
		);
	}

	async compareAndSwapProfile(userId: string, revision: number, update: AvatarProfileUpdate) {
		const current = (await this.readProfile(userId)).data!;
		if (current.avatar_revision !== revision) return { data: null, error: null };
		this.profiles.set(userId, { ...current, ...update });
		return ok({ id: userId });
	}

	async upload(path: string, bytes: Uint8Array): Promise<ProviderResult<null>> {
		if (this.objects.has(path)) return { data: null, error: { message: 'Object already exists.' } };
		this.objects.set(path, bytes.slice());
		return ok(null);
	}

	async remove(paths: string[]): Promise<ProviderResult<null>> {
		for (const path of paths) this.objects.delete(path);
		return ok(null);
	}

	async signedUrl(path: string): Promise<ProviderResult<{ signedUrl: string }>> {
		return this.objects.has(path)
			? ok({ signedUrl: `local-object://${encodeURIComponent(path)}` })
			: { data: null, error: { message: 'Object does not exist.' } };
	}
}
