
---
Task ID: paymob-intention-404-fix
Agent: Main agent (Super Z)
Task: User's live test kept failing with "تعذر بدء الدفع" — diagnose from DockHosting logs and fix the root cause

Work Log:
- Logs user pasted: `[paymob] intention failed ... paymob: decode intention response (http 404): invalid character '<'` — Paymob answered HTML 404 (Django default page), i.e. the ROUTE does not exist, not a key/auth problem
- Live probe confirmed: POST https://accept.paymob.com/api/v1/intention/1 → 404 HTML even unauthenticated; a real route would answer 401 JSON
- Root cause found in official Paymob skill repo (intention-api.md + code-python.md + code-nodejs.md): the Intention endpoint is POST {base}/v1/intention/ — integration ID travels INSIDE the body as payment_methods (integers), NEVER in the URL path; there is no /api prefix
- SECOND critical bug found while fixing: doc says "amount" is integer cents (10000 = 100.00 EGP) but our client divided piastres by 100 to major units → would have charged 1% of the real price (e.g. 100 EGP plan charged as 1 EGP)
- THIRD minor fix: billing_data.country must be 3-letter ISO ("EGY" not "EG")
- client.go fixed: URL {base}/v1/intention/, amount = AmountPiastres as-is, country EGY, package-doc contract updated
- client_test.go: +TestCreateIntentionWireContract (httptest) locking path /v1/intention/, Token auth scheme, integer amount 12500, payment_methods [456987], country EGY, notification_url + special_reference, client_secret/intention_order_id parsing
- api_level 62 → 63 with history comment; go build/vet/test all green (3/3 paymob tests)
- User's env setup was CORRECT (PAYMOB_BASE_URL empty is right — the bug was the path appended in code)

Stage Summary:
- User must Rebuild in DockHosting (health → api_level 63) then retry the payment — same button, same keys, no env changes needed
- Payment ledger hygiene note: the 3 failed payments from the 404 attempts are status='failed' with intent error rows — harmless, retry creates a fresh payment

---
Task ID: paymob-full-audit
Agent: Main agent (Super Z)
Task: User challenged "افحص الكود كامل — يمكن انت اللي غلطت" after persistent 404 "Integration ID does not exist" in Live mode

Work Log:
- Full wire-contract audit of client.go against the official skill repo: path ✓ /v1/intention/, amount piastres ✓, EGY ✓, items name+amount ✓, phone ✓, Token auth ✓, embed URL ✓ (x-frame-options: ALLOWALL observed on accept.paymob.com — iframe embedding is explicitly permitted), HMAC field order ✓ 20 fields
- NEW test locks HMAC concatenation to Paymob's OFFICIAL worked example string (hmac-verification.md line 53) — order+rendering now provably identical to the doc, not just self-consistent
- Found fragility matching the user's exact symptom: payment_methods sends card+wallet together when PAYMOB_WALLET_INTEGRATION_ID is set; ONE bad entry = whole intention 404 "Integration ID does not exist" (doc: Paymob validates every entry). User said "حطيت كل متغيرات البيئة" → likely set a wallet ID that is bad/unmatched in Live
- Fix: client retries ONCE with card-only channels on 404 when >1 channels (self-healing; logs "retrying with card channel only"); +TestCreateIntentionRetriesCardOnlyOn404
- deployment.md §6 wallet row: explicit "leave EMPTY if unused" warning
- api_level 63 → 64; go build/vet/test all green (5/5 paymob tests)
- Remaining external possibilities (not code): Live account has no approved Online Card integration yet (new merchant — support@paymob.com), or card ID from a different mode/account

Stage Summary:
- Code is now provably aligned with Paymob's official contract (5 tests incl. docs worked-example lock)
- After Rebuild: if the card ID is valid, payment works even with a bad wallet ID; if it still 404s, the CARD ID itself is bad for this secret key → dashboard screenshot of Payment Integrations (Live) decides
