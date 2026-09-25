import type { Database } from '$lib/db.types';
import type { SafeSession } from '$lib/auth/session';

type Functions = Database['community_orgs']['Functions'];
export type DomainFunctionName = keyof Functions;
export type DomainFunctionArgs<Name extends DomainFunctionName> = Functions[Name]['Args'];
export type DomainFunctionResult<Name extends DomainFunctionName> = Functions[Name]['Returns'];

export interface ProviderFailure {
	message: string;
	code?: string;
	status?: number;
}

export interface ProviderResult<Value> {
	data: Value | null;
	error: ProviderFailure | null;
}

/** Application-owned port for PostgreSQL domain functions. */
export interface DomainDatabase {
	rpc<Name extends DomainFunctionName>(
		name: Name,
		args?: DomainFunctionArgs<Name>
	): PromiseLike<ProviderResult<DomainFunctionResult<Name>>>;
}

/** A verified request identity, including its current assurance level. */
export interface IdentityProvider {
	verifyRequest(): Promise<SafeSession>;
}

export interface AvatarProfile {
	avatar_path: string | null;
	avatar_source: string;
	avatar_revision: number;
	avatar_url: string | null;
}

export interface AvatarProfileUpdate {
	avatar_path: string | null;
	avatar_source: string;
	avatar_revision: number;
}

/** Account profile persistence and private object storage needed by avatars. */
export interface AvatarProvider {
	readProfile(userId: string): Promise<ProviderResult<AvatarProfile>>;
	compareAndSwapProfile(
		userId: string,
		revision: number,
		update: AvatarProfileUpdate
	): Promise<ProviderResult<{ id: string }>>;
	upload(path: string, bytes: Uint8Array): Promise<ProviderResult<null>>;
	remove(paths: string[]): Promise<ProviderResult<null>>;
	signedUrl(path: string, expiresInSeconds: number): Promise<ProviderResult<{ signedUrl: string }>>;
}

export interface MaintenanceResult {
	health: unknown;
	purgedAnonymousUsers: number;
	abandonedAvatarPaths: string[];
	acquisitions: unknown;
}

/** Provider-neutral maintenance invoked by any authenticated scheduler trigger. */
export interface MaintenanceProvider {
	run(): Promise<MaintenanceResult>;
}

export type ProviderCapability =
	| 'postgresql'
	| 'verified_identity'
	| 'private_storage'
	| 'scheduler'
	| 'secret_references'
	| 'backup_restore'
	| 'migrations';

export type CapabilitySupport = 'supported' | 'external' | 'unsupported';

export interface ProviderDescriptor {
	id: string;
	production: boolean;
	capabilities: Record<ProviderCapability, CapabilitySupport>;
}

export interface RequestProviders {
	descriptor: ProviderDescriptor;
	database: DomainDatabase;
	identity: IdentityProvider;
	avatars: AvatarProvider;
}
