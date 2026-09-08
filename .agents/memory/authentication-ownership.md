---
name: Authentication ownership
description: Product boundary between the public Marketing site and the authenticated Pharmacy App.
---

Marketing should guide users into the Pharmacy App, while the Pharmacy App owns registration, login, session handling, and authenticated account flows.

**Why:** Splitting account creation across two frontends caused redirect, cookie, and unverified-account confusion; keeping the full entry flow in one app gives the session a single origin and clearer user experience.

**How to apply:** New public calls to action should open Pharmacy App registration, and future auth-related screens should be implemented in the Pharmacy App rather than duplicated in Marketing.

The Pharmacy App accepts both `company_user` owners and `employee` identities for pharmacy-scoped reads. The pharmacy scope must come from the authenticated principal; employee-only mutations remain separately protected.

**Why:** Registration in the Pharmacy App creates a company owner account, so rejecting all company users at the pharmacy route boundary made the product reject the very account it had just created.

**How to apply:** Keep owner access tenant-scoped through the principal's assigned pharmacy, and do not broaden employee-only inventory or operational mutations without an explicit company permission model.

Platform-admin and pharmacy authentication are separate realms with separate cookies and endpoints. `super_admin` belongs only to the platform realm; pharmacy access requires an assigned pharmacy.

**Why:** Browser cookies are shared across ports on the same host, so shared auth names allowed an admin session to render the pharmacy shell before API authorization rejected it.

**How to apply:** Preserve realm checks in both session queries and route middleware, and keep each frontend bound to its own realm-specific auth client.

Unverified-account flows should issue verification mail after a correct-password login and when the verification screen opens, while enforcing a short resend cooldown and invalidating tokens when delivery fails.

**Why:** Users commonly return after registration without a valid code; relying only on a manual resend leaves them stuck, while repeated page loads can otherwise invalidate or spam codes.

**How to apply:** Keep one active verification token per principal, treat recent valid tokens as reusable, and allow a failed delivery to be retried immediately.