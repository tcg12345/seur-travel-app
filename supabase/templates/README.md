# Seur account emails

## Confirm signup

- Subject: `Verify your email for Seur`
- HTML body: copy all of `confirmation.html`.
- Dashboard: Seur's Supabase project → Authentication → Email → Templates → Confirm signup.

Keep `{{ .Token }}` exactly as written. Supabase replaces it with the real signup verification code. The template is code-first because the native app verifies the code through `/v1/auth/email/verify`. It does not promise that a confirmation link will sign the user into the app.

The design uses Seur's ivory and bronze palette, a system serif heading, email-safe table layout, inline fallback styles, and optional dark-mode overrides. It has no remote images, fonts, tracking, JavaScript, or dependencies. Clients that do not support dark-mode CSS retain the light design or apply their own colors.

This file is a ready-to-paste template; creating it does not update hosted Supabase Auth. SMTP remains configured separately. After saving it in Supabase, create a new test account and enter the delivered code in the app to check actual inbox delivery and verification. Do not use an old code or the sample code in a preview.

Reference: https://supabase.com/docs/guides/auth/auth-email-templates
