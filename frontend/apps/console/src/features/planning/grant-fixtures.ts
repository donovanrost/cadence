import { decode } from "@/api/index.ts";
import { grantsReader, type Grant, type Grants } from "./grants.ts";

/** Typed automation-grant builders for tests (decoded, so they always satisfy the reader). */
export const activeBody = {
  id: "g1",
  service_identity: { id: "svc_1", name: "Nightly planner" },
  policy_version: 3,
  allowed_actions: ["plan", "submit"],
  maximum_horizon_seconds: 172_800,
  maximum_contacts: 40,
  maximum_execution_concurrency: 2,
  maximum_estimated_cost_micros: null,
  currency: null,
  validity_seconds: 2_592_000,
  valid_from: "2026-11-19T06:40:00Z",
  valid_until: "2026-12-19T06:40:00Z",
  state: "active",
  proposed_by: { id: "u1", name: "Mira K." },
  proposed_at: "2026-11-19T06:40:00Z",
  proposal_expires_at: "2026-11-22T06:40:00Z",
  approved_by: { id: "u2", name: "Ana R." },
  approved_at: "2026-11-19T06:52:00Z",
  reason: "Night shift",
  rejected_by: null,
  rejected_at: null,
  rejection_reason: null,
  withdrawn_by: null,
  withdrawn_at: null,
  revoked_by: null,
  revoked_at: null,
  revocation_reason: null,
  replaces_grant_id: null,
  sha256: "abc",
  viewer_can_narrow: true,
  viewer_can_decide: false,
  cannot_decide_because: "not_proposed",
  cannot_decide_details: null,
  issued_before_two_person_approval: false,
};

export const proposalBody = {
  ...activeBody,
  id: "g2",
  state: "proposed",
  valid_from: null,
  valid_until: null,
  approved_by: null,
  approved_at: null,
  viewer_can_narrow: false,
  viewer_can_decide: true,
  cannot_decide_because: null,
};

export function page(grants: readonly unknown[], extra: Record<string, unknown> = {}): Grants {
  const r = decode(grantsReader, {
    grants,
    service_identities: [{ id: "svc_1", name: "Nightly planner", state: "active" }],
    limits: {
      maximum_horizon_seconds: null,
      maximum_contacts: null,
      maximum_execution_concurrency: null,
    },
    policy_version: 3,
    permissions: ["grants.manage"],
    approval_setting: "independent",
    ...extra,
  });
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
}

/** One decoded grant from `base` with `over` merged in. */
export function grantOf(base: Record<string, unknown>, over: Record<string, unknown> = {}): Grant {
  const [g] = page([{ ...base, ...over }]).grants;
  if (!g) throw new Error("no grant");
  return g;
}

/** A JSON response for a stubbed fetch. */
export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
export const refused = (status: number, code: string, details?: unknown) =>
  json({ error: { code, message: "x", ...(details === undefined ? {} : { details }) } }, status);
