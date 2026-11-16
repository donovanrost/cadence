import type { MissionId } from "@/api/index.ts";
import { decoders as d, request, type ApiResult, type Decoded } from "@/api/index.ts";

/**
 * U68 R3/R4 (api 45563ffe8, parity A3 + A4b/c): one member's release attempts (newest first) and
 * verifiers with the record that matched each (oldest first), 25 a page with cursors. Every
 * vocabulary is knownText, so a new server word shows as itself instead of failing the read.
 */
const attempt = d.object({
  attempt_id: d.token,
  state: d.knownText([
    "release_pending",
    "released",
    "release_failed",
    "release_uncertain",
    "canceled",
  ] as const),
  uncertain: d.boolean,
  // free-text: an internal term (api); Technical details only, never worded.
  failure_reason: d.nullable(d.string),
  /** api's follow-up: why it failed, as a kind and the leading code; optional until it ships. */
  failure: d.optional(
    d.nullable(
      d.object({
        kind: d.knownText(["refused", "resolved", "uncertain"] as const),
        // free-text: refused = the release-stop vocabulary; resolved / uncertain codes vary.
        code: d.nullable(d.string),
        /** For a resolution: who and when (asked of api; optional until it ships). */
        by: d.optional(
          d.nullable(
            d.object({
              id: d.token,
              name: d.nullable(d.string),
              /** api 1b61e57ac: a person or a service identity (an API credential), never Cadence. */
              kind: d.optional(d.nullable(d.knownText(["user", "service_identity"] as const))),
            }),
          ),
        ),
        at: d.optional(d.nullable(d.timestamp)),
      }),
    ),
  ),
  contact: d.nullable(d.object({ id: d.token, label: d.string })),
  path_id: d.nullable(d.token),
  transport_binding_id: d.nullable(d.token),
  encoded_size_bytes: d.nullable(d.integer),
  attempted_at: d.timestamp,
  released_at: d.nullable(d.timestamp),
});

const telemetryEvidence = d.object({
  kind: d.literal("telemetry"),
  sample_id: d.token,
  point_id: d.string,
  point_name: d.nullable(d.string),
  packet_id: d.nullable(d.token),
  evidence_id: d.nullable(d.token),
  quality: d.knownText(["good", "suspect", "bad"] as const),
  raw_value_json: d.nullable(d.string),
  engineering_value_json: d.nullable(d.string),
  /** api 1b61e57ac: the point's catalog unit, null when none; never guessed (ux U70). */
  unit: d.optional(d.nullable(d.string)),
  received_at: d.timestamp,
  generated_at: d.nullable(d.timestamp),
});
const transportEvidence = d.object({
  kind: d.literal("transport"),
  source: d.knownText(["action_request", "capability_record"] as const),
  record_id: d.token,
  // free-text: the action or event kind as the transport records it.
  action: d.string,
  signal_phase: d.nullable(
    d.knownText(["acceptance", "start", "completion", "failure", "custom"] as const),
  ),
  at: d.timestamp,
  recorded_at: d.nullable(d.timestamp),
});
const evidence = d.variant("kind", { telemetry: telemetryEvidence, transport: transportEvidence });

const verifier = d.object({
  instance_id: d.token,
  attempt_id: d.nullable(d.token),
  verifier_id: d.token,
  name: d.nullable(d.string),
  phase: d.knownText(["acceptance", "start", "completion", "custom"] as const),
  severity: d.nullable(d.knownText(["info", "warning", "error", "critical"] as const)),
  state: d.knownText(["pending", "satisfied", "failed", "timed_out", "canceled"] as const),
  failure_code: d.nullable(d.knownText(["timed_out", "failure_criteria_matched"] as const)),
  matched_at: d.nullable(d.timestamp),
  timeout_at: d.nullable(d.timestamp),
  evidence_status: d.knownText(["ready", "unmatched", "unavailable", "pending"] as const),
  evidence: d.nullable(evidence),
});

export const historyReader = d.object({
  request_id: d.token,
  spacecraft_id: d.token,
  attempts: d.array(attempt, 25),
  attempts_next: d.nullable(d.token),
  verifiers: d.array(verifier, 25),
  verifiers_next: d.nullable(d.token),
});
export type History = Decoded<typeof historyReader>;
export type Attempt = History["attempts"][number];
export type HistoryVerifier = History["verifiers"][number];

export function fetchHistory(
  missionId: MissionId,
  requestId: string,
  cursors: Readonly<{ attempts?: string | null; verifiers?: string | null }> = {},
  signal?: AbortSignal,
): Promise<ApiResult<History>> {
  const params = new URLSearchParams();
  if (cursors.attempts) params.set("attempts_after", cursors.attempts);
  if (cursors.verifiers) params.set("verifiers_after", cursors.verifiers);
  const q = params.size ? `?${params.toString()}` : "";
  return request(
    `/missions/${encodeURIComponent(missionId)}/command-requests/${encodeURIComponent(requestId)}/history${q}`,
    historyReader,
    signal ? { signal } : {},
  );
}
