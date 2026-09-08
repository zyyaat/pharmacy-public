---
name: Session restoration
description: Access and refresh cookie behavior during frontend auth bootstrap.
---

Both frontend auth clients must allow a failed `/auth/me` request to call `/auth/refresh` before treating the user as signed out. Other authentication endpoints should not trigger an automatic refresh.

**Why:** The access cookie is intentionally short-lived, while the refresh cookie persists longer. Excluding every `/auth/*` endpoint from refresh made a normal page reload look like a logout after access expiry.

**How to apply:** Keep `credentials: 'include'`, send the CSRF cookie on refresh, and limit automatic refresh to `/auth/me` plus ordinary authenticated API requests.