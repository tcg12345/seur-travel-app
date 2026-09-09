# Seur account setup

Updated September 8, 2026.

## Implemented

The native app uses one account flow in onboarding, Profile and Travel. It supports native Apple identity tokens with a random nonce, Google OAuth with S256 PKCE, and email signup with verification before a Seur session can be issued. Passwords must be 8–256 characters. Email codes support one-time-code autofill and resend cooldowns. Existing username-only accounts can still sign in; accounts are never merged by display name or username.

The Edge Function verifies identity with Supabase Auth and returns only Seur's revocable opaque session. Provider tokens and service credentials remain server-side. Authorization uses the verified Auth user ID, never editable profile metadata. Profile editing is scoped to the current session owner.

## Apple

Completed: enable Sign in with Apple on App ID `com.seurapp.travel`, refresh Xcode provisioning, and enable the Apple provider in Supabase with that bundle ID. The signed device build now contains the capability. Real Apple account consent still needs an on-device sign-in to verify end to end.

This integration is native Apple sign-in. It does not require the rotating client secret used by Apple's web OAuth flow.

## Google — configuration still required

An existing Google Cloud account can be reused. Give Seur its own OAuth client; a separate Cloud project also keeps its consent-screen branding independent from another app.

1. Configure a Google consent screen for Seur (basic identity scopes: openid, email and profile).
2. Create an OAuth client of type **Web application**. Seur uses Supabase's hosted Google OAuth flow in the iOS authentication session, not the native Google SDK.
3. Add this authorized redirect URI exactly:
   `https://bwrodcxmdzrpyrshrlfd.supabase.co/auth/v1/callback`
4. In Seur's Supabase project → Authentication → Sign In / Providers → Google, save the client ID and client secret and enable Google.
5. If the consent screen is in Testing, add the intended Google test users. Complete Google's publishing requirements before general release.

Do not put the Google client secret in the iOS app or source control. The app reads provider availability so it enables Google only after Supabase is configured.

## Email — SMTP configuration still required

The existing email-provider account can be reused. Configure a sender address/domain for Seur and its SPF/DKIM records, then enter the provider's SMTP host, port, username and password in Seur's Supabase Authentication email settings. Use the Seur sender name/address. No email-provider credential belongs in the app.

Already configured remotely:
- Email confirmations enabled; unverified email sign-in disabled.
- Password minimum: 8.
- Confirmation template contains both the verification link and numeric code.
- Site URL and redirect allowlist: `seur://auth/callback`.
- OTP length: 8; expiry: one hour.

Supabase's built-in mail delivery is restricted and does not replace production SMTP. Actual inbox delivery remains unverified until the sender is configured. The local config enables confirmations too; provider credentials remain environment-specific and should not be overwritten by a whole-config push.

## Verification

- 43 native account/domain tests passed.
- 28 Edge Function tests passed, including verification, provider-token validation boundaries and existing document-sharing contracts.
- Live disposable-account checks passed: unverified login blocked, valid OTP accepted, invalid/reused OTP rejected, eight-character login accepted, profile ownership enforced, forged Apple token rejected, logout revoked the session.
- The live test used Auth Admin link generation without sending an email and deleted the disposable user afterward.
- Two terminal-driven UI tests passed for account navigation and the shared onboarding flow.
- Signed iPhone build passed after refreshing Apple provisioning and was installed on Tyler’s iPhone.
- Security review: service-only recap tables intentionally have RLS without client policies. Supabase's existing leaked-password protection warning remains; consider enabling it in Auth password settings if supported by the plan.

## References

- [Supabase native Apple authentication](https://supabase.com/docs/guides/auth/social-login/auth-apple)
- [Supabase Google authentication](https://supabase.com/docs/guides/auth/social-login/auth-google)
- [Supabase custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp)
- [Password protection settings](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
