
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
