import sharp from 'sharp';
import type { User } from '@supabase/supabase-js';
import { AVATAR_MAX_BYTES, AVATAR_MIME_TYPES } from '$lib/avatar';

export class AvatarError extends Error {}

export async function normaliseAvatar(bytes: Uint8Array, contentType: string): Promise<Buffer> {
	if (!bytes.length || bytes.length > AVATAR_MAX_BYTES)
		throw new AvatarError('Choose an image smaller than 2 MB.');
	if (!AVATAR_MIME_TYPES.includes(contentType))
		throw new AvatarError('Choose a JPEG, PNG or WebP image.');
	try {
		const image = sharp(bytes, { limitInputPixels: 25000000, failOn: 'warning' });
		const metadata = await image.metadata();
		if (!['jpeg', 'png', 'webp'].includes(metadata.format ?? '') || (metadata.pages ?? 1) > 1) {
			throw new Error('Unsupported image');
		}
		// auto-orient before resizing; Sharp strips metadata by default.
		return await image
			.rotate()
			.resize(512, 512, { fit: 'inside', withoutEnlargement: true })
			.webp({ quality: 85 })
			.toBuffer();
	} catch {
		throw new AvatarError('This image could not be read. Choose a still JPEG, PNG or WebP image.');
	}
}

// Exact provider-owned image hosts and path shapes. Never accept a URL supplied
// in form data, or arbitrary editable user_metadata, for a server-side fetch.
export function allowedProviderPhoto(value: unknown): string | null {
	if (typeof value !== 'string') return null;
	try {
		const url = new URL(value);
		if (url.protocol !== 'https:' || url.username || url.password || url.port || url.hash)
			return null;
		const allowed =
			(url.hostname === 'avatars.githubusercontent.com' && /^\/u\/\d+$/.test(url.pathname)) ||
			(/^lh[3-6]\.googleusercontent\.com$/.test(url.hostname) &&
				/^\/(a|a-)\/[A-Za-z0-9_=/.-]+$/.test(url.pathname)) ||
			(url.hostname === 'cdn.discordapp.com' &&
				/^\/avatars\/\d+\/[a-zA-Z0-9_]+\.(png|jpg|webp)$/.test(url.pathname));
		return allowed ? url.href : null;
	} catch {
		return null;
	}
}

export function providerPhoto(user: User): string | null {
	for (const identity of user.identities ?? []) {
		if (!['google', 'github', 'discord'].includes(identity.provider)) continue;
		const url = allowedProviderPhoto(
			identity.identity_data?.avatar_url ?? identity.identity_data?.picture
		);
		if (url) return url;
	}
	return null;
}

export async function downloadProviderPhoto(
	url: string,
	fetcher: typeof fetch = fetch
): Promise<Buffer> {
	if (!allowedProviderPhoto(url))
		throw new AvatarError('This provider photo cannot be imported. Upload a photo instead.');
	// Redirects are rejected rather than allowing an external host to choose a
	// second fetch destination. The timeout covers streaming the response too.
	const response = await fetcher(url, {
		redirect: 'error',
		signal: AbortSignal.timeout(8000),
		headers: { Accept: 'image/jpeg,image/png,image/webp' }
	});
	if (!response.ok || !response.body)
		throw new AvatarError('The provider photo is unavailable. Upload a photo instead.');
	const type = response.headers.get('content-type')?.split(';')[0].trim() ?? '';
	if (
		!AVATAR_MIME_TYPES.includes(type) ||
		Number(response.headers.get('content-length')) > AVATAR_MAX_BYTES
	) {
		await response.body.cancel();
		throw new AvatarError('The provider photo is not a supported image under 2 MB.');
	}
	const reader = response.body.getReader();
	const chunks: Uint8Array[] = [];
	let length = 0;
	try {
		while (true) {
			const { done, value } = await reader.read();
			if (done) break;
			length += value.length;
			if (length > AVATAR_MAX_BYTES)
				throw new AvatarError('The provider photo is larger than 2 MB.');
			chunks.push(value);
		}
	} finally {
		await reader.cancel();
	}
	return normaliseAvatar(Buffer.concat(chunks), type);
}
