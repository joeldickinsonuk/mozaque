# Mozaque

Mozaque is a native Flutter app for iPhone and Android: private shared galleries, meaningful dates, invitations, uploads, saved Pieces, Glows, and anniversary Echoes. It uses Supabase Auth, Postgres Row Level Security, and a private Supabase Storage bucket.

## Connect a Supabase project

The app is connected to the `mozaque` Supabase project. Its initial schema is in `supabase/migrations/20260929212907_mozaque_initial_schema.sql` and has been applied. The app uses the project's URL and **publishable key**, which are intended for mobile clients; Row Level Security protects user data. Never use a Supabase secret or service-role key in the app.

## First slice

- Email and password sign up/sign in, with a first-name profile.
- A feed showing only photos from galleries you can access.
- Create named galleries with event type, date, recurrence, visibility, and upload rules.
- Invite-only galleries and galleries shared with all of your connections.
- Time-limited invitation codes and `mozaque://invite` links.
- JPG, PNG, and WebP uploads up to 10 MB, with private signed photo URLs.
- Owner-only, selected-contributor, and everyone-invited upload rules.
- Freeze a gallery into a preserved memory.
- Save photos as Pieces, react with Glows, and resurface annual dates as Echoes.

## Run

```sh
flutter pub get
flutter run
```

## Publish a web preview

The GitHub Actions workflow in `.github/workflows/pages.yml` builds the Flutter web app and publishes it to GitHub Pages whenever changes are pushed to `main`. In the repository settings, set **Pages → Build and deployment → Source** to **GitHub Actions**. The workflow automatically builds for the repository's `/REPOSITORY/` URL path.

Before inviting testers, add the published Pages URL to **Supabase → Authentication → URL Configuration → Redirect URLs** so confirmation and recovery links can return to the app. The Supabase client publishable key is included in the web app; keep all secret and service-role keys out of client code.

For account confirmation, set the Supabase Auth email confirmation and redirect settings for the app you plan to ship. Invitation codes also work by copy/paste when a deep link cannot launch the app.
