# Bow brand lookup Worker

This Worker keeps the Logo.dev Search and Context.dev API keys out of the iPhone app. It exposes only `GET /search?q=...` and `POST /identify` with `{ "descriptor": "..." }`. It sends no account, amount, or transaction date to either provider.

1. In Cloudflare **Workers & Pages**, create a Worker from the GitHub repository containing this app. Select the `main` branch, set **Root directory** to `brand-worker`, leave **Build command** blank, and use the default `npx wrangler deploy` deploy command. Cloudflare will give it a `workers.dev` URL; no purchased domain is needed.
2. In the Worker's **Settings → Variables and Secrets**, add `LOGO_DEV_SECRET_KEY` as a runtime **Secret**. Add `CONTEXT_DEV_API_KEY` as a runtime **Secret** when ready to enable enrichment of file and SimpleFIN transactions. Never put either key in `wrangler.jsonc` or the iPhone project. Rotate any secret previously shared in chat before production.
3. Copy the deployed HTTPS Worker URL into `BOW_BRAND_LOOKUP_BASE_URL` in the app's `Project.json` and rebuild. Company suggestions are disabled until this URL is set. Name-based Logo.dev images and local payees continue to work without the Worker.

Alternatively, from this directory, install Node.js and run `npm install` followed by `npm run deploy` after authenticating Wrangler with the Cloudflare account. The rate-limit bindings in `wrangler.jsonc` are required; the Worker returns an error rather than calling a provider if a binding is missing.

Search and identification are rate limited by Cloudflare per IP address. Responses are cached by a hash of the input. This provides basic quota protection for testing; a larger public release should add app attestation or user authentication. The app still supports local payees when this Worker is unavailable.
