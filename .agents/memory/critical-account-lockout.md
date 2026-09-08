---
name: Critical account lockout policy
description: Security policy for protecting privileged platform accounts without making them easy to disable.
---

Privileged platform accounts must not be disabled by updating their account-level lockout state after failed passwords. Apply failed-login throttling to the credential-and-source combination instead, so a remote attacker cannot deny service to the owner account while ordinary accounts retain their normal protection.

**Why:** Account-wide lockouts let anyone who knows an email address disable the most important account with a few bad requests.

**How to apply:** Keep a short-lived rate limit for the Super Admin email plus source IP, return `429` rather than `423`, allow a correct password to recover immediately, and add MFA as the next high-impact control.