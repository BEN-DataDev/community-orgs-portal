import { randomUUID } from 'node:crypto';
import type { User } from '@supabase/supabase-js';
import type { TypedSupabaseClient } from '$lib/supabase-client';
import type { AccountAvatar, AvatarSource } from '$lib/avatar';
import { AvatarError, providerPhoto } from './avatar-image';

const BUCKET = 'avatars';
export const AVATAR_URL_TTL = 900;
const fields = 'avatar_path, avatar_source, avatar_revision, avatar_url' as const;

export async function loadAccountAvatar(
	client: TypedSupabaseClient,
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
	const { data, error } = await client
		.schema('public')
		.from('users')
		.select(fields)
		.eq('id', user.id)
		.maybeSingle();
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
		const { data: signed, error: signError } = await client.storage
			.from(BUCKET)
			.createSignedUrl(data.avatar_path, AVATAR_URL_TTL);
		if (!signError && signed) {
			result.url = signed.signedUrl;
			result.expiresAt = Date.now() + AVATAR_URL_TTL * 1000;
		}
	} else if (data.avatar_source === 'provider') {
		result.url = externalPhoto;
	}
	return result;
}

async function removeFile(client: TypedSupabaseClient, path: string): Promise<boolean> {
	try {
		const { error } = await client.storage.from(BUCKET).remove([path]);
		return !error;
	} catch {
		return false;
	}
}

export async function saveAccountAvatar(
	client: TypedSupabaseClient,
	userId: string,
	revision: number,
	source: AvatarSource,
	image?: Buffer
): Promise<{ cleanupPending: boolean }> {
	const { data: old, error: readError } = await client
		.schema('public')
		.from('users')
		.select(fields)
		.eq('id', userId)
		.single();
	if (readError || !old)
		throw new AvatarError('Could not load your avatar settings. Reload and try again.');
	if (old.avatar_revision !== revision)
		throw new AvatarError('Your avatar changed in another tab. Reload before trying again.');
	if (source === 'upload' && !image) throw new AvatarError('Choose an image to upload.');
	const path = source === 'upload' ? `${userId}/avatar-${randomUUID()}.webp` : null;
	if (path && image) {
		const { error } = await client.storage
			.from(BUCKET)
			.upload(path, image, { contentType: 'image/webp', upsert: false, cacheControl: '300' });
		if (error) throw new AvatarError('Could not upload your photo. Please try again.');
	}
	// Compare-and-swap prevents a slow request overwriting a newer choice.
	// On ambiguous network failures, leave the staged file for daily cleanup:
	// the database may have committed, so deleting it could break the avatar.
	const { data: saved, error: saveError } = await client
		.schema('public')
		.from('users')
		.update({ avatar_path: path, avatar_source: source, avatar_revision: revision + 1 })
		.eq('id', userId)
		.eq('avatar_revision', revision)
		.select('id')
		.maybeSingle();
	if (saveError || !saved) {
		if (!saveError && path) await removeFile(client, path);
		throw new AvatarError(
			'Could not save your avatar, or it changed in another tab. Reload and try again.'
		);
	}
	const cleanupPending =
		old.avatar_path && old.avatar_path !== path
			? !(await removeFile(client, old.avatar_path))
			: false;
	return { cleanupPending };
}
