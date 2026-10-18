import {
  array,
  bool,
  count,
  id,
  invalid,
  nullable,
  object,
  oneOf,
  record,
  text,
} from "../../../shared/readers.ts";

const hash = (value: unknown) => {
  const result = text(value);
  return /^[a-f0-9]{64}$/.test(result) ? result : invalid();
};
const bounded =
  (max: number, min = 0) =>
  (value: unknown) => {
    const result = count(value);
    return result >= min && result <= max ? result : invalid();
  };
export const readProtocol = object({
  downlink: oneOf(["tm", "aos", "uslp"]),
  uplink: oneOf(["tc", "uslp"]),
  frame_size: bounded(65536, 1),
  secondary_header_length: bounded(255),
  insert_zone_length: bounded(65535),
  ocf_length: oneOf([0, 4]),
  truncated_primary_header: bool,
});
const documentFields = object({
  catalog_revision_id: nullable(id),
  telemetry_enabled: bool,
  commanding_enabled: bool,
  telemetry_source_endpoint_id: nullable(id),
  handled_apids: array(bounded(2047), 2048),
  protocol: nullable(readProtocol),
});
export function readDocument(value: unknown) {
  const document = documentFields(value);
  if (new Set(document.handled_apids).size !== document.handled_apids.length) return invalid();
  const protocol = document.protocol;
  if (
    protocol &&
    protocol.secondary_header_length + protocol.insert_zone_length + protocol.ocf_length >=
      protocol.frame_size
  )
    return invalid();
  return document;
}
export type ConfigurationDocument = ReturnType<typeof readDocument>;
export type Protocol = ReturnType<typeof readProtocol>;
export const section = oneOf(["overview", "catalog", "communications", "changes"]);
export type Section = ReturnType<typeof section>;
export type Inspector = "catalog" | "telemetry" | "commanding";
const catalog = object({
  id,
  name: text,
  label: text,
  declarations: count,
  packets: count,
  commands: count,
  href: text,
});
const fields = object({
  organization_id: id,
  mission_id: id,
  spacecraft_id: id,
  mission_name: text,
  name: text,
  scid: nullable(count),
  section,
  base_href: text,
  token: hash,
  saved_version: nullable(count),
  document: readDocument,
  external_changes: bool,
  active: nullable(object({ version: count, generation: count, document: readDocument })),
  approval: object({
    requirement: oneOf(["direct", "independent"]),
    token: hash,
    source: oneOf(["organization", "inherited", "overridden", "enforced"]),
    actor_id: id,
    can_request: bool,
    can_review: bool,
  }),
  review: nullable(
    object({
      id,
      state: oneOf(["active", "stale", "approval_pending", "approved", "rejected"]),
      version: count,
      requester_id: id,
    }),
  ),
  catalogs: array(catalog),
  fleet_total: count,
  fleet: array(
    object({
      id,
      name: text,
      scid: nullable(count),
      active_catalog_id: nullable(id),
      has_changes: bool,
      href: text,
    }),
  ),
  sources: array(object({ id, name: text })),
  presets: array(object({ id, version: count, name: text, protocol: readProtocol })),
  links: object({
    catalog: text,
    identity: text,
    applications: text,
    communications: text,
    readiness: text,
    approvals: text,
    settings: text,
    ops: nullable(text),
  }),
});
export type ConfigurationSnapshot = ReturnType<typeof fields>;
export type ConfigurationIdentity = Readonly<{
  organizationId: string;
  missionId: string;
  spacecraftId: string;
}>;
export function readConfiguration(
  value: unknown,
  expected?: ConfigurationIdentity,
): ConfigurationSnapshot {
  const result = fields(value);
  const mission = `/missions/${result.mission_id}`;
  const base = `${mission}/spacecraft/${result.spacecraft_id}`;
  if (
    expected &&
    (result.organization_id !== expected.organizationId ||
      result.mission_id !== expected.missionId ||
      result.spacecraft_id !== expected.spacecraftId)
  )
    return invalid();
  if (
    result.base_href !== base ||
    !result.fleet.some((craft) => craft.id === result.spacecraft_id) ||
    result.fleet.some(
      (craft) => craft.href !== `${mission}/spacecraft/${craft.id}?section=${result.section}`,
    ) ||
    result.catalogs.some(
      (revision) => revision.href !== `${mission}/catalog/revisions/${revision.id}`,
    )
  )
    return invalid();
  const links = result.links;
  if (
    links.catalog !== `${mission}/catalog` ||
    links.identity !== `${base}/identity` ||
    links.applications !== `${base}/applications` ||
    links.readiness !== `${base}/readiness` ||
    links.communications !== `${mission}/comms` ||
    links.approvals !== `${mission}/ops/activations` ||
    links.settings !== `${mission}/settings/cadence.governance`
  )
    return invalid();
  if (links.ops !== null) {
    const target = new URL(links.ops, "https://cadence.invalid");
    if (
      target.origin !== "https://cadence.invalid" ||
      target.pathname !== `${mission}/ops/commands/workspace` ||
      target.searchParams.size !== 1 ||
      !result.sources.some((source) => source.id === target.searchParams.get("target")) ||
      !result.active?.document.commanding_enabled
    )
      return invalid();
  }
  for (const ids of [
    result.fleet.map((item) => item.id),
    result.sources.map((item) => item.id),
    result.catalogs.map((item) => item.id),
  ])
    if (new Set(ids).size !== ids.length) return invalid();
  return result;
}
export const readPackets = object({
  catalog_id: id,
  packets: array(object({ apid: bounded(2047), name: text, definitions: count }), 2048),
});
export type PacketChoices = ReturnType<typeof readPackets>;
export type WriteResult =
  | { status: "ok"; message: string }
  | { status: "rejected" | "unconfirmed"; message: string };
export type ConfigurationPort = Readonly<{
  save(token: string, document: ConfigurationDocument): Promise<WriteResult>;
  review(token: string, policyToken: string): Promise<WriteResult>;
  activate(token: string, policyToken: string): Promise<WriteResult>;
  decide(
    token: string,
    requestId: string,
    reason: string,
    decision: "approved" | "rejected",
  ): Promise<WriteResult>;
  catalog(id: string): Promise<PacketChoices>;
}>;
export function createConfigurationPort(
  send: (event: string, input: Record<string, unknown>) => Promise<unknown>,
): ConfigurationPort {
  async function write(event: string, input: Record<string, unknown>): Promise<WriteResult> {
    try {
      const result = record(await send(event, input));
      if (result.status === "ok") return { status: "ok", message: text(result.message) };
      if (result.status === "rejected")
        return { status: "rejected", message: text(result.message) };
      return invalid();
    } catch {
      return {
        status: "unconfirmed",
        message:
          "The result could not be confirmed. Your edits are preserved; check the saved version before trying again.",
      };
    }
  }
  return {
    save: (token, document) => write("save", { token, document }),
    review: (token, policyToken) => write("review", { token, policy_token: policyToken }),
    activate: (token, policyToken) => write("activate", { token, policy_token: policyToken }),
    decide: (token, requestId, reason, decision) =>
      write("decide", { token, request_id: requestId, reason, decision }),
    async catalog(id) {
      const result = record(await send("catalog", { id }));
      if (result.status !== "ok")
        throw new Error(
          typeof result.message === "string"
            ? result.message
            : "Packet definitions are unavailable.",
        );
      const packets = readPackets(result.data);
      if (
        packets.catalog_id !== id ||
        new Set(packets.packets.map((packet) => packet.apid)).size !== packets.packets.length
      )
        return invalid();
      return packets;
    },
  };
}
