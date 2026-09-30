# Mozaque email templates

These branded HTML templates are ready to paste into **Supabase Dashboard → Authentication → Emails → Templates**. Set the sender name to **Mozaque** in the SMTP settings.

| Supabase template | Suggested subject | File |
| --- | --- | --- |
| Confirm signup | Finish setting up your Mozaque | `confirmation.html` |
| Reset password | Reset your Mozaque password | `recovery.html` |
| Invite user | There’s a private Mozaque invitation for you | `invite.html` |
| Magic link | Your sign-in link for Mozaque | `magic_link.html` |
| Change email | Confirm your new email for Mozaque | `email_change.html` |
| Reauthentication | Your Mozaque security code | `reauthentication.html` |
| Password changed notification | Your Mozaque password was changed | `password_changed_notification.html` |
| Email changed notification | Your Mozaque email address was changed | `email_changed_notification.html` |

## Delivery setup

The hosted project is on Supabase Free and was created after 3 June 2026. Supabase’s shared default SMTP service does not allow new Free projects to customize Auth email templates, and it is restricted to project-organization addresses with a low hourly limit. To use these templates and send to you and your partner, configure a custom SMTP provider first. See [Supabase’s SMTP guide](https://supabase.com/docs/guides/auth/auth-smtp).

After configuring SMTP:

1. Set the sender display name to `Mozaque` and a verified sender address.
2. Paste each file into its matching Auth email template and apply the suggested subject.
3. Add the hosted web origin plus `mozaque://recovery` and `mozaque://invite**` to **Authentication → URL Configuration → Redirect URLs**.
4. Test signup confirmation and password recovery with both accounts.

The app’s gallery and connection invitations are composed in the device share sheet, not sent by Supabase Auth. The app now supplies a personal subject and message with the inviter’s name, Mozaque title, join link/code, and expiry. Supabase’s `Invite user` template is included for a future flow that sends account invitations directly through Supabase Auth.

Supabase Auth generates confirmation and reset messages; an SMTP provider delivers them. The default hosted SMTP is suitable only for early testing, while production Auth email delivery should use a provider you configure and verify.
