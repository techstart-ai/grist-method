# Auth v2 PRD

## Problem Statement

Enterprise customers cannot use the product because we do not support SSO. Three deals worth a combined $480k ARR are blocked in procurement awaiting OIDC support. Every week we delay loses one expansion conversation.

## Goal

Ship OIDC-based SSO with Okta as the first IdP, generic OIDC support to follow within the same quarter. The existing email/password path must continue to work for non-enterprise tenants without behavioural change.

## Non-Goals

- SAML support (slated for next quarter)
- Social login (Google/GitHub) — not requested by enterprise pipeline
- MFA redesign (current TOTP flow remains)

## Invariants

- Sessions must not exceed 8h without re-auth
- No PII in JWT claims
- Existing email/password path unchanged for free-tier tenants

## Epics

### Okta OIDC integration

Stories: S1.1, S1.2, S1.3

### Session refresh

Stories: S2.1, S2.2

## Acceptance Criteria

- Okta sign-in works end-to-end for the test tenant
- Refresh is transparent to the user — no re-prompt within 8h
- Logout revokes the session everywhere (no zombie tokens)

## Risks

- Token rotation race: mitigation is a refresh cron with exponential backoff
- Okta downtime: mitigation is a 1h grace cache for valid sessions

## Non-Functional Requirements

- p95 latency under 200ms for /auth/* endpoints
- Audit log every signin and signout event
- 99.9% availability for the OIDC broker
