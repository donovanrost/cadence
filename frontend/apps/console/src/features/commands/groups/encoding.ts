import type { MissionId } from "@/api/index.ts";
import {
  detailsOf,
  isError,
  isKnown,
  decoders as d,
  describeApiError,
  request,
  type Decoded,
} from "@/api/index.ts";

/**
 * M24 encode preview for Approve A3 (commanding.md §encoding): the command payload bytes release
 * would send, from the request's own model revision. Payload only, before transport framing. A
 * request whose revision isn't active fails closed (409 encode_unavailable); the console never
 * falls back to the current catalog.
 */
const encodingReader = d.object({
  command_request_id: d.token,
  command_id: d.token,
  // free-text: decoded for completeness, never shown or branched on (no vocabulary in the contract)
  scope: d.token,
  size_bytes: d.integer,
  hex: d.string,
});
export type Encoding = Decoded<typeof encodingReader>;

export type EncodingView =
  | Readonly<{ ok: true; encoding: Encoding }>
  | Readonly<{ ok: false; reason: string }>;

/** commanding.md encode_unavailable: why a request's bytes can't be shown. */
const encodeReasons = [
  "revision_superseded",
  "revision_not_active",
  "basis_unavailable",
  "encode_failed",
] as const;
const REASONS: Readonly<Record<(typeof encodeReasons)[number], string>> = {
  revision_superseded: "the catalog revision it was submitted against has been superseded",
  revision_not_active: "its catalog revision isn't active",
  basis_unavailable: "its encoding basis isn't available",
  encode_failed: "encoding failed",
};
const unavailable = d.object({
  /** A reason REASONS words; a newer one reads as words. */
  reason: d.knownText(encodeReasons),
  detail: d.optional(d.nullable(d.string)),
});

export async function fetchEncoding(
  missionId: MissionId,
  requestId: string,
  signal?: AbortSignal,
): Promise<EncodingView> {
  const r = await request(
    `/missions/${encodeURIComponent(missionId)}/command-requests/${encodeURIComponent(requestId)}/encoding`,
    encodingReader,
    signal ? { signal } : {},
  );
  if (r.ok) return { ok: true, encoding: r.value };
  const e = r.error;
  const why = isError(e, "encode_unavailable") ? detailsOf(e, unavailable) : null;
  if (why) {
    {
      const words = isKnown(why.reason)
        ? REASONS[why.reason]
        : why.reason.unrecognized.replaceAll("_", " ");
      // Only an encoder failure's detail is words; the others carry a revision id.
      const detail = why.reason === "encode_failed" ? why.detail : null;
      return { ok: false, reason: `${words}${detail ? ` (${detail})` : ""}` };
    }
  }
  return { ok: false, reason: describeApiError(e) };
}

/** "0A 00 07": bytes in pairs, at most `max` shown. */
export function hexBytes(hex: string, max = 32): string {
  const pairs = hex.toUpperCase().match(/.{1,2}/g) ?? [];
  const shown = pairs.slice(0, max).join(" ");
  return pairs.length > max ? `${shown} …` : shown;
}
