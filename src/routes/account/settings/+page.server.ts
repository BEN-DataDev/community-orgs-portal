import { requestEmailChange } from '$lib/server/email-change';
import { needsMfaChallenge } from '$lib/auth/session';
import { AVATAR_MAX_BYTES } from '$lib/avatar';
import {
	AvatarError,
	normaliseAvatar,
	providerPhoto,
	downloadProviderPhoto
} from '$lib/server/avatar-image';
import { saveAccountAvatar } from '$lib/server/account-avatar';
import { fail } from '@sveltejs/kit';
import { z } from 'zod';
import type { Actions } from './$types';

const nameSchema = z
	.string()
	.trim()
	.min(1, 'Enter a display name.')
	.max(80, 'Use 80 characters or fewer.');

export const actions: Actions = {
	default: async ({ request, locals, url }) => {
		// Layout loads do not protect actions; enforce account access here too.
		if (!locals.user || locals.isAnonymous)
			return fail(403, { error: 'Sign in with an account to change settings.' });
		if (!locals.aal || needsMfaChallenge(locals.aal))
			return fail(403, { error: 'Complete verification before changing settings.' });
		// Bound the complete multipart body, including chunked requests, before
		// parsing it. The file itself has the stricter 2 MB limit below.
		const reader = request.body?.getReader();
		const chunks: Uint8Array[] = [];
		let size = 0;
		if (reader) {
			try {
				while (true) {
					const { done, value } = await reader.read();
					if (done) break;
					size += value.length;
					if (size > AVATAR_MAX_BYTES + 65536) {
						await reader.cancel();
						return fail(413, { error: 'Choose an image smaller than 2 MB.' });
					}
					chunks.push(value);
				}
			} finally {
				reader.releaseLock();
			}
		}
		let fields: FormData;
		try {
			fields = await new Response(Buffer.concat(chunks), {
				headers: { 'content-type': request.headers.get('content-type') ?? '' }
			}).formData();
		} catch {
			return fail(400, { error: 'Could not read the form. Please try again.' });
		}
		const intent = fields.get('intent') ?? 'profile';
		if (intent === 'emailChange' || intent === 'emailResend') {
			return requestEmailChange(locals, fields, url.origin, intent === 'emailResend');
		}
		if (intent !== 'profile') {
			const revisionValue = fields.get('avatarRevision');
			const revision =
				typeof revisionValue === 'string' && /^\d+$/.test(revisionValue)
					? Number(revisionValue)
					: NaN;
			if (!Number.isSafeInteger(revision) || revision < 0 || revision >= 2147483647)
				return fail(400, { error: 'Reload your avatar settings and try again.' });
			try {
				let image: Buffer | undefined;
				if (intent === 'uploadAvatar') {
					const file = fields.get('avatar');
					if (!(file instanceof File)) throw new AvatarError('Choose an image to upload.');
					image = await normaliseAvatar(new Uint8Array(await file.arrayBuffer()), file.type);
				} else if (intent === 'importAvatar') {
					const url = providerPhoto(locals.user);
					if (!url)
						throw new AvatarError(
							'No supported provider photo is available. Upload a photo instead.'
						);
					image = await downloadProviderPhoto(url);
				} else if (intent !== 'removeAvatar' && intent !== 'providerAvatar') {
					return fail(400, { error: 'Unknown account action.' });
				}
				const source = image ? 'upload' : intent === 'providerAvatar' ? 'provider' : 'initials';
				const { cleanupPending } = await saveAccountAvatar(
					locals.providers.avatars,
					locals.user.id,
					revision,
					source,
					image
				);
				return {
					message: cleanupPending
						? 'Avatar saved. The previous file will be cleaned up later.'
						: 'Avatar updated.'
				};
			} catch (error) {
				return fail(400, {
					error:
						error instanceof AvatarError
							? error.message
							: 'Could not update your avatar. Please try again.'
				});
			}
		}
		const parsed = nameSchema.safeParse(fields.get('displayName'));
		if (!parsed.success) return fail(400, { error: parsed.error.issues[0].message });
		const { data, error } = await locals.supabase.auth.updateUser({
			data: { display_name: parsed.data }
		});
		if (error) return fail(400, { error: 'Could not save your name. Please try again.' });
		locals.user = data.user;
		return { success: true };
	}
};
