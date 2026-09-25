import { randomUUID } from 'node:crypto';
import type { User } from '@supabase/supabase-js';
import type { AccountAvatar, AvatarSource } from '$lib/avatar';
import type { AvatarProvider } from '$lib/server/providers/contracts';
import { AvatarError, providerPhoto } from './avatar-image';

export const AVATAR_URL_TTL = 900;

export async function loadAccountAvatar(
	provider: AvatarProvider,
	user: User
): Promise<AccountAvatar> {
	const fallback: AccountAvatar = {
		source: 'initials',
		url: null,
		expiresAt: null,
		revision: 0,
		available: false,
		canImportProvider: !!providerPhoto(user),
		hasProviderPhoto: false
	};
	const { data, error } = await provider.readProfile(user.id);
	if (error || !data) return fallback;
	let externalPhoto: string | null = null;
	try {
		const url = new URL(data.avatar_url ?? providerPhoto(user) ?? '');
		if (url.protocol === 'https:' && !url.username && !url.password) externalPhoto = url.href;
	} catch {
		/* An account without a provider photo uses initials. */
	}
	const result: AccountAvatar = {
		...fallback,
		available: true,
		hasProviderPhoto: !!externalPhoto,
		revision: data.avatar_revision,
		source: data.avatar_source as AvatarSource
	};
	if (data.avatar_source === 'upload' && data.avatar_path) {
		const { data: signed, error: signError } = await provider.signedUrl(
			data.avatar_path,
			AVATAR_URL_TTL
		);
		if (!signError && signed) {
			result.url = signed.signedUrl;
			result.expiresAt = Date.now() + AVATAR_URL_TTL * 1000;
		}
	} else if (data.avatar_source === 'provider') {
		result.url = externalPhoto;
	}
	return result;
}

async function removeFile(provider: AvatarProvider, path: string): Promise<boolean> {
	try {
		const { error } = await provider.remove([path]);
		return !error;
	} catch {
		return false;
	}
}

export async function saveAccountAvatar(
	provider: AvatarProvider,
	userId: string,
	revision: number,
	source: AvatarSource,
	image?: Buffer
): Promise<{ cleanupPending: boolean }> {
	const { data: old, error: readError } = await provider.readProfile(userId);
	if (readError || !old)
		throw new AvatarError('Could not load your avatar settings. Reload and try again.');
	if (old.avatar_revision !== revision)
		throw new AvatarError('Your avatar changed in another tab. Reload before trying again.');
	if (source === 'upload' && !image) throw new AvatarError('Choose an image to upload.');
	const path = source === 'upload' ? `${userId}/avatar-${randomUUID()}.webp` : null;
	if (path && image) {
		const { error } = await provider.upload(path, image);
		if (error) throw new AvatarError('Could not upload your photo. Please try again.');
	}
	// Compare-and-swap prevents a slow request overwriting a newer choice.
	// On ambiguous network failures, leave the staged file for daily cleanup:
	// the database may have committed, so deleting it could break the avatar.
	const { data: saved, error: saveError } = await provider.compareAndSwapProfile(userId, revision, {
		avatar_path: path,
		avatar_source: source,
		avatar_revision: revision + 1
	});
	if (saveError || !saved) {
		if (!saveError && path) await removeFile(provider, path);
		throw new AvatarError(
			'Could not save your avatar, or it changed in another tab. Reload and try again.'
		);
	}
	const cleanupPending =
		old.avatar_path && old.avatar_path !== path
			? !(await removeFile(provider, old.avatar_path))
			: false;
	return { cleanupPending };
}
