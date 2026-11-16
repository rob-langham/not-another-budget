# Longview

Long-term budgeting app, built from the Longview design.

- **App:** Flutter (Android, iOS, web) — `app/`
- **API:** Kotlin + Ktor — `backend/`
- **Storage:** SQLite (one file)
- **Sign-in:** Auth0 (Google, Apple, GitHub or any Auth0 social connection)

```mermaid
flowchart LR
  U[Flutter app] -- "1 · Sign in (Universal Login,<br/>connection=google-oauth2 …)" --> A[Auth0]
  A -- "2 · Access token (JWT)" --> U
  U -- "3 · /api/* + Bearer token" --> K[Ktor API]
  K -- "4 · Check signature (JWKS)" --> A
  K <--> D[(SQLite)]
  M[Inbound email provider] -- "Amazon order emails" --> K
```

## Features (one per design screen)

| Screen | What it does |
|---|---|
| Overview | Savings goal vs pace, catch-up advice, monthly bars, income, budget, outliers, accounts, bills this week |
| Transactions | By day or by category, search, filter, change category, see split items |
| Ideal budget | Bills, yearly costs (set aside monthly) and spending pots; auto "Paid" ticks; find repeats from history |
| Outliers | Spending outside the plan; "Make it recurring" / "Keep as one-off" when a payment repeats |
| Accounts | Daily end-of-day balances, balance overrides, logo (auto / website / social / upload / letter), manual accounts |
| Import | Upload CSV → columns auto-matched (saved per account) → preview with duplicates skipped |
| Amazon receipts | Forward or paste an order email → matched to the card payment → split into categories |
| Categories & rules | Your categories; rules on merchant, description, amount, weekday, time, account |

## Run it locally (no Auth0 needed)

1. Start the API with dev sign-in:

```bash
cd backend && DEV_AUTH=true ./gradlew run
```

2. (Optional) load demo data that matches the design:

```bash
python3 tools/seed_demo.py --user demo
```

3. Run the app as that user:

```bash
cd app && flutter run -d chrome --dart-define=DEV_USER=demo --dart-define=API_BASE_URL=http://localhost:8080
```

> ⚠️ `DEV_AUTH=true` accepts `Bearer dev:<name>` with no password. Never turn it on in production.

## Auth0 setup

1. **Create an API** (Applications → APIs). Identifier e.g. `https://api.longview.app`. This is the *audience*.
2. **Create an application** of type *Native* (mobile) and one of type *Single Page Application* (web).
3. **Callback / logout URLs**
   - Android: `app.longview://YOUR_DOMAIN/android/app.longview.longview/callback`
   - iOS: `app.longview://YOUR_DOMAIN/ios/app.longview.longview/callback`
   - Web: your site origin, e.g. `http://localhost:3000` (also add it to *Allowed Web Origins*)
4. **Social connections** (Authentication → Social): turn on Google, Apple, GitHub, … and enable them for both applications. The login buttons pass `connection=<name>`; change the list with `--dart-define=AUTH0_CONNECTIONS=google-oauth2:Google,apple:Apple`.
5. **Run the API**

```bash
cd backend && AUTH0_DOMAIN=your-tenant.eu.auth0.com AUTH0_AUDIENCE=https://api.longview.app ./gradlew run
```

6. **Run the app**

```bash
cd app && flutter run --dart-define=AUTH0_DOMAIN=your-tenant.eu.auth0.com --dart-define=AUTH0_CLIENT_ID=YOUR_CLIENT_ID --dart-define=AUTH0_AUDIENCE=https://api.longview.app --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

   For Android builds also pass `-Pauth0Domain=your-tenant.eu.auth0.com` (or set `AUTH0_DOMAIN`), used by `android/app/build.gradle.kts`.

## API settings (environment variables)

| Variable | Meaning | Default |
|---|---|---|
| `AUTH0_DOMAIN` | Your tenant, e.g. `x.eu.auth0.com` | — |
| `AUTH0_AUDIENCE` | API identifier | — |
| `DB_PATH` | SQLite file | `data/longview.db` |
| `PORT` | HTTP port | `8080` |
| `CORS_HOSTS` | Allowed web origins, comma separated (empty = any) | empty |
| `RECEIPTS_EMAIL_DOMAIN` | Domain in the forwarding address | `receipts.longview.app` |
| `INBOUND_EMAIL_SECRET` | Secret your mail provider sends as `X-Webhook-Secret` | — (webhook off) |
| `DEV_AUTH` | Local dev sign-in | `false` |

## Tests

```bash
cd backend && ./gradlew test
```

```bash
cd app && flutter test
```

The backend tests replay the design's numbers: £3,870 saved, £397 behind, "save an extra £199", "Paid 1 Nov", "£315 of £540 put by", Amex CSV auto-matching, receipt splits, and that users can't see each other's data.

## Not built yet

- 🏦 **Bank links (Monzo/Starling sync).** Needs an open-banking provider (e.g. TrueLayer, GoCardless). `POST /api/accounts/{id}/sync` returns "not connected yet". CSV import works for every bank.
- 📧 **Receiving emails.** Point an inbound-email service (Postmark, Mailgun, SendGrid) at `POST /webhooks/inbound-email` with body `{"to": "...", "text": "..."}`. Until then, use "Paste an order email".
- 📄 OFX/QIF files (CSV only for now).
- 🔤 Fonts: the app asks for Inter / Space Grotesk but doesn't bundle them; add them to `pubspec.yaml` to match the design exactly.

## How money and dates are stored

- Amounts are whole pence (`Long`/`int`). Negative = money out.
- Dates are `yyyy-MM-dd` text; times `HH:mm`.
