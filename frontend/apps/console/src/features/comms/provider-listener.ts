import {
  decoders as d,
  detailsOf,
  isError,
  isKnown,
  type ApiError,
  type Unrecognized,
} from "@/api";
import { STOPS_SHARING } from "./listener.ts";

/**
 * #202 (#129): a provider-managed transport's Listener, own or shared. Cadence owns the choice; the
 * endpoint, framing and authentication come from the provider (changes.md, TCP listener choice).
 * The choice is offered only while derive says the delivery listens for downlink
 * (`preview.listener_eligible`). A stored choice that is missing reads as Own.
 */

export const listenerChoices = ["own", "shared"] as const;
export type ListenerChoice = (typeof listenerChoices)[number];

/** The transport kind schema's option words (changes.md). */
export const listenerWords: Readonly<Record<ListenerChoice, string>> = {
  own: "Own listener for each pass",
  shared: "Shared, routed by SCID",
};
export const listenerOptions = listenerChoices.map((value) => ({
  value,
  label: listenerWords[value],
}));

type Doc = Readonly<Record<string, unknown>>;

/** The stored choice: Shared only when the document says so (missing is Own, api). */
export function storedListener(doc: Doc): ListenerChoice {
  const config = doc["configuration"];
  if (typeof config !== "object" || config === null || !("listener" in config)) return "own";
  return config.listener === "shared" ? "shared" : "own";
}

/**
 * What the transport will use: the form's choice while the delivery can share, else Own. A stored
 * Shared that can no longer share goes back to Own in the same stage (api).
 */
export const effectiveListener = (choice: ListenerChoice, eligible: boolean): ListenerChoice =>
  eligible ? choice : "own";

/** The edit hides the choice over a stored Shared one: it will stop sharing (U83's words). */
export const stopsSharing = (stored: Doc, eligible: boolean | null): string | null =>
  eligible === false && storedListener(stored) === "shared" ? STOPS_SHARING : null;

/** The stage refusal codes on `configuration.listener` (changes.md). */
export const listenerCodes = [
  "invalid_listener_choice",
  "shared_listener_requires_downlink",
  "shared_listener_requires_tm_framing",
  "shared_listener_requires_allowlist",
  "shared_listener_requires_mtls",
  "shared_listener_unavailable_mtls",
  "listen_endpoint_listener_mismatch",
  "shared_listener_bind_mismatch",
] as const;
type ListenerCode = (typeof listenerCodes)[number];

const codeWords: Readonly<Record<ListenerCode, string>> = {
  invalid_listener_choice: "Choose Own listener for each pass or Shared, routed by SCID.",
  shared_listener_requires_downlink: "Only a downlink transport that listens can share one.",
  shared_listener_requires_tm_framing: "A shared listener needs fixed-size TM frames.",
  shared_listener_requires_allowlist:
    "A plaintext shared listener needs the provider's source addresses. Ask the provider to add them, or keep Own.",
  shared_listener_requires_mtls:
    "Another transport already listens on this endpoint without mutual TLS. Sharing it across providers needs mutual TLS.",
  shared_listener_unavailable_mtls:
    "Mutual TLS needs a provider-managed transport with an enrolled delivery credential.",
  listen_endpoint_listener_mismatch:
    "Another transport on this endpoint uses the other listener setting. Transports on one endpoint must agree on Own or Shared.",
  shared_listener_bind_mismatch: "Shared listeners on this port must use the same bind address.",
};

const refusal = d.object({
  errors: d.array(
    d.object({
      /** Only the listener's path matters here; any other reads as unrecognized. */
      path: d.nullable(d.knownText(["configuration.listener"] as const)),
      // free-text: the kind's refusal sentence, shown when the code is unknown.
      message: d.string,
      code: d.optional(d.nullable(d.knownText(listenerCodes))),
    }),
    200,
  ),
});

function words(
  e: Readonly<{ message: string; code?: ListenerCode | Unrecognized | null | undefined }>,
): string {
  return e.code && isKnown(e.code) ? codeWords[e.code] : e.message;
}

/** A refused stage's error on the Listener, in words; null when the refusal is elsewhere. */
export function stageListenerRefusal(error: ApiError): string | null {
  if (!isError(error, "invalid_op")) return null;
  const hit = detailsOf(error, refusal)?.errors.find((e) => e.path !== null && isKnown(e.path));
  return hit ? words(hit) : null;
}
