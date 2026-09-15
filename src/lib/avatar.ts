export const AVATAR_MAX_BYTES = 2 * 1024 * 1024;
export const AVATAR_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
export type AvatarSource = 'provider' | 'upload' | 'initials';
export interface AccountAvatar {
	source: AvatarSource;
	url: string | null;
	expiresAt: number | null;
	revision: number;
	available: boolean;
	canImportProvider: boolean;
	hasProviderPhoto: boolean;
}
