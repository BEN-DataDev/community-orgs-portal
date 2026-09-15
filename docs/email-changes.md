# Email changes

Account Settings uses `auth.updateUser({ email }, { emailRedirectTo })` with the
signed-in user's client. It requires a permanent account and a verified MFA session
when enrolled. The Auth user ID, profile row, avatar path and organisation roles
are not changed. Provider accounts can request a portal email change; this does not
change an email at the external provider.

The form validates the address and confirmation, rejects the current address and
an already-pending duplicate, and shows `user.new_email` until confirmed. Resend
uses `auth.resend({ type: 'email_change', email: user.email })`: Supabase looks up
the account by its current address, not the pending one. Rate limits and delivery
failures are surfaced without exposing raw Auth errors.

Keep Secure email change enabled in the hosted project's Auth settings. Local
`supabase/config.toml` already sets `double_confirm_changes = true`. The app does
not disable confirmations or use the admin API to change users' addresses.

The checked-in `supabase/templates/email_change.html` is the local template and
can also be copied to the hosted Email Templates screen. Existing token-hash
email-change templates remain compatible even if their `next` destination points
to an older page: `/auth/confirm` sends email-change results to `/auth/email-change`.
The first successful confirmation may return neither user nor session; it displays
“One more confirmation”, not success. Only a verified response with a session and
no pending address reports completion. Expired/reused links offer a route back to
Settings. Short-lived, HTTP-only result cookies avoid displaying status from an
unverified query parameter. Token hashes are stripped from the redirect.

Requests also provide `/auth/email-change` as `emailRedirectTo`, supporting the
hosted default `ConfirmationURL` template through its PKCE code exchange. The app
handles a legacy first-confirmation message conservatively and never treats it as
completion. Allow this redirect URL in the project's Auth redirect allowlist; the
existing local wildcard allowlist already covers it. Keep the project's Site URL
pointing at the deployed app when using the custom token-hash template.

Run `npm run test:email-changes`, `npm run check`, and `npm run build`. Automated
checks mock Auth responses and do not send emails. They cover validation, access
and MFA guards, pending state, resend, partial/final verification, error handling,
and compatibility with password-recovery confirmation links. Real delivery and
confirmation from both inboxes require an integration check against the configured
mail provider; no production email was sent as part of implementation.
