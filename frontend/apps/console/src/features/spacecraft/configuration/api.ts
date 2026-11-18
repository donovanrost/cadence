import type { MissionId, SpacecraftId } from "@/api/index.ts";
import {
  decoders as d,
  request,
  spacecraftId as spacecraftIdReader,
  scid as scidReader,
  type ApiResult,
  type Decoded,
} from "@/api/index.ts";

/**
 * (B) a spacecraft's configuration workspace (director 11-17; ux U94; api's shape diff, ported
 * from the host's SpacecraftConfigurationPage). Its own subtree, so Investigate's
 * `GET …/spacecraft/:sc/configuration` read stays as it is. Approve and reject stay on L10.
 */
/** On with api's (B) set 1 routes (picked together, lead 11-18); the craft's page links here. */
export const CONFIGURATION_WORKSPACE_LIVE = true;

export const workspacePath = (missionId: MissionId, spacecraftId: SpacecraftId) =>
  `/missions/${encodeURIComponent(missionId)}/spacecraft/${encodeURIComponent(spacecraftId)}/configuration/workspace`;

/** The host's ConfigurationInput framing; the people setting it know these terms (U94). */
export const protocolReader = d.object({
  downlink: d.knownText(["tm", "aos", "uslp"] as const),
  uplink: d.knownText(["tc", "uslp"] as const),
  frame_size: d.integer,
  secondary_header_length: d.integer,
  insert_zone_length: d.integer,
  ocf_length: d.integer,
  truncated_primary_header: d.boolean,
});
export type Protocol = Decoded<typeof protocolReader>;

/**
 * The editable configuration document (the host's ConfigurationInput keys), WITHOUT the
 * Telemetry and Commanding switches: change sets own them (#109), so they come read-only in
 * `switches`, and a draft carrying them is refused (422). Never sent back.
 */
export const documentReader = d.object({
  catalog_revision_id: d.nullable(d.token),
  telemetry_source_endpoint_id: d.nullable(d.token),
  handled_apids: d.array(d.integer, 2048),
  protocol: d.nullable(protocolReader),
});
export type ConfigurationDocument = Decoded<typeof documentReader>;

/**
 * DECISIONS #109: change sets own both switches, always. `set` false: no change set has set it
 * (value reads false); `revision` is the change-set revision that last set it, when known.
 */
const switchReader = d.object({
  value: d.boolean,
  set: d.boolean,
  revision: d.nullable(d.integer),
});
export type SwitchState = Decoded<typeof switchReader>;

export const sections = ["overview", "catalog", "communications", "changes"] as const;
export const reviewStates = [
  "approval_pending",
  "approved",
  "rejected",
  "withdrawn",
  "superseded",
  "stale",
  "active",
] as const;

export const snapshotReader = d.object({
  spacecraft_id: spacecraftIdReader,
  // free-text: the spacecraft's display name
  name: d.string,
  scid: d.nullable(scidReader),
  section: d.knownText(sections),
  /** Opaque; sent back on save and submit, never shown (U94: Technical details only). */
  // free-text: an opaque concurrency token
  token: d.string,
  /** Per craft (v1, v2…); null: never saved, so the document is derived. */
  saved_version: d.nullable(d.integer),
  document: documentReader,
  external_changes: d.boolean,
  /** null: nothing runs for this craft yet (U94 "Not set up"). */
  active: d.nullable(
    d.object({ version: d.integer, generation: d.integer, document: documentReader }),
  ),
  review: d.nullable(
    d.object({
      id: d.token,
      state: d.knownText(reviewStates),
      requester_id: d.token,
      version: d.nullable(d.integer),
    }),
  ),
  approval: d.object({
    requirement: d.knownText(["direct", "independent"] as const),
    // free-text: an opaque policy token, sent back on submit
    policy_token: d.string,
    source: d.knownText(["organization", "inherited", "overridden", "enforced"] as const),
    can_request: d.boolean,
    can_review: d.boolean,
  }),
  catalogs: d.array(
    d.object({
      id: d.token,
      // free-text: the catalog's name and revision label, shown as the host does
      name: d.string,
      // free-text: see name
      label: d.string,
      declarations: d.integer,
      packets: d.integer,
      commands: d.integer,
      /** The catalog revision number, for U65's "catalog rev 14"; optional until api adds it. */
      number: d.optional(d.integer),
    }),
    500,
  ),
  /** At most 100 here; fleet_total counts them all. */
  fleet: d.array(
    d.object({
      id: spacecraftIdReader,
      // free-text: a spacecraft's display name
      name: d.string,
      scid: d.nullable(scidReader),
      active_catalog_id: d.nullable(d.token),
      has_changes: d.boolean,
    }),
    100,
  ),
  fleet_total: d.integer,
  // free-text: a packet source's display name
  sources: d.array(d.object({ id: d.token, name: d.string }), 500),
  presets: d.array(
    d.object({
      id: d.token,
      version: d.integer,
      // free-text: a framing preset's name
      name: d.string,
      protocol: protocolReader,
    }),
    200,
  ),
  /** #109: the switches' only source (read-only; lead kept the per-switch form). */
  switches: d.object({ telemetry_enabled: switchReader, commanding_enabled: switchReader }),
});
export type ConfigurationSnapshot = Decoded<typeof snapshotReader>;
export type ConfigurationSection = ConfigurationSnapshot["section"];

export type WorkspaceKey = Readonly<{
  missionId: MissionId;
  spacecraftId: SpacecraftId;
  section: (typeof sections)[number];
}>;

/** GET …/configuration/workspace?section=… (api's (B) set 1). */
export function fetchWorkspace(
  k: WorkspaceKey,
  signal: AbortSignal,
): Promise<ApiResult<ConfigurationSnapshot>> {
  return request(
    `${workspacePath(k.missionId, k.spacecraftId)}?section=${encodeURIComponent(k.section)}`,
    snapshotReader,
    { signal },
  );
}

/** GET …/workspace/catalogs/:id/packets: the packet choices for a catalog revision. */
export const packetChoicesReader = d.object({
  catalog_id: d.token,
  /** The 14 in "catalog rev 14" (api); optional until shipped. */
  catalog_number: d.optional(d.integer),
  packets: d.array(
    // free-text: a packet's name from the catalog
    d.object({ apid: d.integer, name: d.string, definitions: d.integer }),
    2048,
  ),
});
export type PacketChoices = Decoded<typeof packetChoicesReader>;

export function fetchPacketChoices(
  missionId: MissionId,
  spacecraftId: SpacecraftId,
  catalogRevisionId: string,
  signal?: AbortSignal,
): Promise<ApiResult<PacketChoices>> {
  return request(
    `${workspacePath(missionId, spacecraftId)}/catalogs/${encodeURIComponent(catalogRevisionId)}/packets`,
    packetChoicesReader,
    signal ? { signal } : {},
  );
}

/** POST …/workspace/submit's answer (writes land in a later commit, once the route exists). */
export const submitResultReader = d.variant("state", {
  approval_pending: d.object({
    state: d.literal("approval_pending"),
    request_id: d.token,
  }),
  active: d.object({ state: d.literal("active") }),
  /** Approved, but the application couldn't be confirmed yet (U94: U38/U91 words). */
  needs_review: d.object({ state: d.literal("needs_review") }),
});
export type SubmitResult = Decoded<typeof submitResultReader>;
