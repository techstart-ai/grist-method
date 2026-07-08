# PRD: Auth v2 — Enterprise SSO (OIDC)

**Status:** Planning
**Author:** Product Management
**Inputs:** brief.md, Q3 enterprise pipeline review, procurement feedback from Northwind, Contoso, and Fabrikam
**Last updated:** 2026-07-08

---

## 1. Executive Summary

This document proposes Auth v2, an initiative to add OpenID Connect (OIDC) based single sign-on to the product, with Okta as the first supported identity provider and generic OIDC support following within the same quarter. Today, every user — regardless of plan — authenticates with an email address and a password that we store and manage ourselves. That model has served us well through the self-serve and mid-market phases of the business, but it has become the single most frequently cited blocker in enterprise procurement conversations. Three active deals, worth a combined $480,000 in annual recurring revenue, are currently stalled in security review specifically because we cannot federate authentication to the customer's identity provider.

The proposal is deliberately narrow. We will build an OIDC broker service that handles the Okta handshake, exchange authorization codes for tokens on the backend, store sessions server-side in Redis with an eight-hour ceiling, and refresh those sessions transparently so users are not re-prompted mid-workday. We will not touch the existing email/password flow, we will not implement SAML this quarter, and we will not redesign MFA. The existing login experience for free-tier and self-serve tenants must be byte-for-byte identical after this ships.

If we execute on the plan described here, we expect to unblock the three stalled deals within the quarter, remove SSO from the top of the "reasons lost" column in our CRM, and establish the session infrastructure that SAML and SCIM provisioning will later build on. If we do nothing, the enterprise pipeline continues to erode: our sales engineering lead estimates we lose roughly one expansion conversation per week to this gap, and two of the three blocked accounts have told us directly that they will re-open their evaluation of competitors if we cannot commit to a date.

## 2. Background & Current State

A short summary of how authentication works today, for reviewers who have not worked in this part of the codebase. Every account is identified by an email address and a bcrypt-hashed password stored in our primary Postgres database. On successful login we issue a signed JWT to the browser, which the client presents on every request; a "remember me" option extends the token's validity to 30 days. There is no server-side session record, which means there is no way to revoke a token before it expires — if a laptop is stolen or an employee is offboarded, the token remains valid until it ages out. Our optional MFA is a TOTP implementation we built in 2023, enabled on roughly 11% of accounts.

This architecture was a reasonable trade-off when the product was self-serve and the median customer had six seats. It is increasingly untenable at enterprise scale, for three reasons. First, the 30-day client-held token is exactly the pattern enterprise security teams screen against — Fabrikam's review called it out by name. Second, offboarding is a real operational problem for large tenants: when an employee leaves Northwind, their IT team expects deactivating the Okta account to end access to every connected application immediately, and we cannot honor that today. Third, password management at scale generates measurable support load on both sides — our tickets, and the customer's help desk.

It is also worth stating what we are *not* claiming: the current system is not insecure for the self-serve segment it was designed for, and nothing in this document should be read as a plan to migrate existing password users. The two authentication paths will coexist. The invariant that the email/password path remains unchanged is there precisely so that this project cannot quietly become a rewrite of login for everyone.

Prior art inside the company: a 2024 spike explored SAML using a third-party library and was shelved when the sponsoring deal fell through; its main lesson — that we need a broker service boundary between IdP protocols and our session model rather than wiring IdP logic into the monolith — directly shapes the architecture proposed for this project. The session-store component described in the accompanying architecture document (Redis-backed, opaque tokens, server-side revocation) is the piece that makes both this quarter's OIDC work and next quarter's SAML work possible.

## 3. Problem Statement

Enterprise customers cannot adopt the product because we do not support single sign-on. This is not a soft preference or a nice-to-have on a security questionnaire — it is a hard procurement gate. In each of the three blocked deals, the customer's security team has a written policy requiring that all third-party SaaS applications federate authentication to the corporate identity provider. A vendor that requires separately managed passwords fails the review automatically, before pricing or functionality is even discussed.

### Customer evidence

- **Northwind Traders** ($210k ARR, 400 seats): Security review completed in May. The only open finding is "no SSO/OIDC support." Their IT director told our account executive, verbatim, that "we cannot roll out another password to 400 people; our board audit explicitly flags non-federated SaaS." Deal is paused, not dead, but their internal champion has warned us that budget reallocates at the end of the quarter.
- **Contoso Ltd.** ($175k ARR, 300 seats): Procurement returned our security questionnaire with SSO marked as a mandatory requirement. They use Okta Workforce Identity across roughly 40 other SaaS vendors and expect a standard OIDC integration with their existing tenant. They have offered to act as a design partner and test against their sandbox Okta org, which materially de-risks our rollout.
- **Fabrikam Inc.** ($95k ARR, 150 seats): Smaller deal, same story. Their CISO's team rejected the current password-based flow and additionally flagged that they require sessions to expire within one working day. Our current 30-day remember-me token was cited as a specific finding.

Beyond the three named accounts, the pattern is systemic. Sales engineering reviewed the last two quarters of enterprise-segment losses and found SSO cited in 9 of 14. Every week we delay, we lose roughly one expansion conversation — sometimes silently, because prospects who screen vendors on a security checklist never enter the pipeline at all, which means the visible $480k understates the real cost.

There is also an internal cost worth acknowledging. Support currently handles a steady stream of password-reset tickets from larger tenants (about 6% of all tickets last quarter), and our own security posture would improve by delegating credential management for enterprise users to identity providers that enforce the customer's own MFA and device policies.

## 4. Goals & Success Metrics

The primary goal is to ship OIDC-based SSO with Okta as the first identity provider, with generic OIDC support (any spec-compliant IdP) following within the same quarter. The existing email/password path must continue to work for non-enterprise tenants with no behavioral change whatsoever.

Success will be measured as follows:

- **G1 — Revenue unblock:** All three blocked deals (Northwind, Contoso, Fabrikam) pass security review on the authentication line item within 30 days of GA. Target: $480k ARR moved out of "blocked" status.
- **G2 — Sign-in reliability:** ≥ 99.5% of Okta sign-in attempts complete successfully end-to-end (excluding failures caused by customer-side IdP misconfiguration, which we will track separately) during the first 60 days.
- **G3 — Transparent refresh:** Fewer than 0.5% of active enterprise sessions experience a visible re-authentication prompt within the 8-hour session window. Refresh must be invisible to the user.
- **G4 — Zero regression:** No statistically significant change in login success rate, latency, or support-ticket volume for email/password tenants, measured over the 30 days after rollout compared to the 30 days before.
- **G5 — Time-to-configure:** A customer admin with an existing Okta tenant can configure the integration in under 30 minutes using our documentation, without contacting support. Validated with Contoso as design partner.

## 5. Non-Goals

We are explicitly not doing the following in this release, and it is worth recording why, because each of these has been requested at least once and will come up again in review:

- **SAML support.** SAML remains common in older enterprise stacks, and at least one prospect has asked for it. It is deliberately slated for next quarter: the protocol surface is larger, the XML signature handling is a well-known source of security bugs, and none of the three blocked deals require it — all three run Okta with OIDC available. Building the OIDC broker first gives SAML a foundation to slot into.
- **Social login (Google/GitHub sign-in).** Nobody in the enterprise pipeline has requested it, and it would complicate the account-linking model at exactly the moment we need the session layer to stay simple. If self-serve growth ever demands it, it becomes a separate PRD.
- **MFA redesign.** The current TOTP flow remains exactly as it is for password-based accounts. Enterprise users signing in through Okta will get whatever MFA their organization enforces at the IdP, which is strictly better than anything we would build this quarter.
- **SCIM user provisioning and deprovisioning.** Customers will eventually want automatic seat management driven from their directory. It is out of scope here; user records are still created just-in-time on first SSO sign-in.
- **Admin UI for IdP configuration.** For the first release, integration setup is docs-plus-support-assisted. A self-serve configuration screen ships with generic OIDC support later in the quarter.

## 6. User Personas

- **Priya, enterprise end user.** A project manager at Northwind with 40 browser tabs and no patience for extra passwords. She expects to click "Sign in with SSO," bounce through her company's Okta page (where she is usually already authenticated), and land in the product. She should never see our password form, and she should never be interrupted mid-afternoon by a session prompt.
- **Marcus, customer IT administrator.** Runs the Okta tenant at Contoso. He has configured dozens of OIDC integrations and has strong expectations: standard authorization-code flow, a clearly documented redirect URI, discovery document support, and error messages that name the actual misconfiguration. He is the persona for G5.
- **Dana, customer security reviewer.** Never uses the product day-to-day but decides whether anyone else may. She cares about session lifetime ceilings, what claims we put in tokens, whether logout actually revokes, and whether sign-in events are auditable. Several requirements below exist purely to satisfy Dana.
- **Sam, our support engineer.** Will field the "SSO login is broken" tickets. Needs sign-in failures logged with enough structure to distinguish our bug from the customer's IdP misconfiguration in under five minutes.

## 7. Functional Requirements

### Epic E1 — Okta OIDC integration

This epic gates all three deals. It covers the full round trip from "Sign in with SSO" click to an authenticated product session, brokered through a new backend service so that raw tokens never reach the browser.

- **S1.1 — Okta OIDC handshake endpoint.** Implement the authorization-code callback: `POST /auth/okta/callback` receives the authorization code, exchanges it for tokens via the Okta SDK on the backend, persists the session server-side, and sets an httpOnly session cookie. The client receives an opaque session identifier only — never the raw JWT — so that we retain the ability to revoke sessions before token expiry. Invalid or replayed codes return 401 without leaking detail.
- **S1.2 — Tenant-to-IdP mapping and login initiation.** When a user enters their email on the login screen, detect whether their tenant has SSO configured and route them to the Okta authorization endpoint with the correct client ID, scopes, and state parameter. Tenants without SSO see the password flow, unchanged. State must be validated on return to prevent CSRF on the callback.
- **S1.3 — Just-in-time account linking and first-login provisioning.** On first successful Okta sign-in, match the verified email claim to an existing account in the tenant, or create a new user record if the tenant allows JIT provisioning. Existing password-based accounts that match are linked, not duplicated; the user keeps their history, permissions, and content.

### Epic E2 — Session refresh

Sessions are capped at eight hours (a hard invariant — see below), but a hard cap with a hard prompt would make Priya re-authenticate mid-workday. This epic makes the cap invisible.

- **S2.1 — Backend token refresh.** Refresh tokens are held and exercised exclusively on the backend; a scheduled refresh job renews Okta tokens before expiry with exponential backoff on transient failures. The client never sees a refresh token, eliminating the most common token-leak vector.
- **S2.2 — Session lifecycle and revocation.** Sliding renewal within the 8-hour window, absolute expiry at 8 hours requiring full re-authentication, and logout that revokes the session everywhere — server-side session destroyed, cookie cleared, and no "zombie token" capable of authenticating a subsequent request from any device.

## 8. Invariants

These hold regardless of implementation choices, and reviewers should treat any design that violates them as broken:

1. **Sessions must not exceed 8 hours without re-authentication.** This is a direct procurement requirement from Fabrikam's CISO and consistent with the other two accounts' policies.
2. **No PII in JWT claims.** Tokens must carry opaque subject identifiers only — no email addresses, no names — so that a leaked or logged token discloses nothing about the person.
3. **The existing email/password path is unchanged for free-tier tenants.** No new screens, no new redirects, no latency regression, no copy changes.

## 9. Acceptance Criteria

- **AC1:** Okta sign-in works end-to-end for the test tenant: from the login page, through the Okta hosted sign-in, back to an authenticated session in the product, verified against Contoso's sandbox org.
- **AC2:** Refresh is transparent — a user active within the 8-hour window is never shown a re-authentication prompt, and an idle user's session still resolves without a prompt when they return within the window.
- **AC3:** Logout revokes the session everywhere. After logout, no cookie, cached token, or replayed request authenticates; a revoked session is unusable within 5 seconds across all nodes.
- **AC4:** A free-tier tenant's login experience is unchanged, verified by the existing end-to-end login test suite passing without modification.

## 10. Risks & Mitigations

- **R1 — Token rotation race (medium).** Concurrent requests near token expiry can trigger competing refresh attempts; Okta rotates refresh tokens on use, so the loser of the race holds a dead token and the user is logged out. *Mitigation:* refresh is performed by a single backend cron with exponential backoff, and in-flight requests use the existing session rather than triggering refresh themselves.
- **R2 — Okta downtime (low).** If Okta is unreachable, users cannot complete a fresh sign-in — acceptable — but already-authenticated users should not be ejected mid-session. *Mitigation:* a 1-hour grace cache honors valid, unexpired sessions during an IdP outage; new sign-ins fail with a clear status message.
- **R3 — Account-linking mistakes (medium).** JIT linking on email match could attach an SSO identity to the wrong account if a tenant has stale or shared mailboxes. *Mitigation:* link only on verified email claims, log every link event to the audit trail, and provide a support runbook for unlinking.
- **R4 — Design-partner schedule slip (low).** Contoso's sandbox availability drives AC1 validation. *Mitigation:* our own Okta developer org is the fallback test tenant; Contoso validates but does not gate.

## 11. Non-Functional Requirements

- p95 latency under 200ms for all `/auth/*` endpoints, measured at the load balancer.
- Every sign-in and sign-out event is written to the audit log with timestamp, tenant, opaque user ID, IdP, and outcome — retained for 400 days to satisfy customer audit cycles.
- 99.9% availability for the OIDC broker service, with health checks and alerting from day one.
- Secrets (client secrets, signing keys) live in the existing secrets manager; nothing IdP-related is committed to configuration files.

## 12. Rollout Plan

1. **Phase 0 — Internal dogfood (week 1 after code-complete):** our own staff tenant switches to Okta sign-in. Bugs here cost nothing.
2. **Phase 1 — Design partner (weeks 2–3):** Contoso sandbox, then Contoso production behind a tenant-level feature flag. Daily check-ins with Marcus's team; G5 timing measured here.
3. **Phase 2 — Blocked-deal onboarding (weeks 3–5):** Northwind and Fabrikam onboarded with support-assisted configuration.
4. **Phase 3 — GA (week 6):** feature flag defaults on for all enterprise-plan tenants; documentation published; sales enablement brief delivered.
Rollback at every phase is the feature flag: disabling it returns a tenant to password authentication without data loss, since SSO-created accounts are ordinary accounts.

## 13. Open Questions

- **Q1:** Do we require Okta sign-in to *replace* password login for a tenant, or may both coexist? Dana-type reviewers usually want passwords disabled once SSO is on; needs confirmation from all three accounts before Phase 2.
- **Q2:** Session length — is 8 hours the right ceiling for every enterprise tenant, or does this need to be tenant-configurable (4–8h) at GA? Fabrikam hinted at 4 hours for privileged roles.
- **Q3:** What is the support escalation path for IdP misconfiguration during the beta — do we give Sam's team read access to broker logs directly?

## 14. Stakeholders

- **Product:** PM for identity & platform (owner of this document)
- **Engineering:** platform team lead (delivery owner), 2 backend engineers, 1 frontend engineer
- **Design:** login-flow UX review only; no new surfaces beyond the SSO button and error states
- **Sales engineering:** owns customer-facing configuration docs review and the three blocked-account relationships
- **Security:** internal review of token handling and session model before Phase 1
- **Support:** runbook sign-off before Phase 2
