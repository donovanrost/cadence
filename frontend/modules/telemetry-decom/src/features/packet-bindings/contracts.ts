import type { HostActionReceipt } from "@cadence/plugin-sdk";
export type Endpoint = { id: string; label: string };
export type Packet = {
  id: string;
  name: string;
  apid: number;
  field_count: number;
  compatible_field_count: number;
  selectable: boolean;
  detail_href: string;
};
export type Resource = {
  id: string;
  path: string;
  type: string;
  size_bits: number | null;
  compatible: boolean;
};
export type Page<T> = {
  items: T[];
  total_count: number;
  page: number;
  page_size: 25;
  previous_href: string | null;
  next_href: string | null;
};
export type PacketDocument = {
  contract_version: 1;
  context: {
    organization_id: string;
    mission_id: string;
    spacecraft_id: string;
    actor_id: string;
    installation_id: string;
  };
  spacecraft_name: string;
  review_token: string;
  query: {
    page: number;
    endpoint_page: number;
    resource_page: number;
    q: string;
    endpoint_q: string;
    packet: string;
  };
  configuration: {
    id: string | null;
    version: number;
    catalog_revision_id: string;
    catalog_label: string;
    catalog_version: number;
    enabled: boolean;
  } | null;
  input: { id: "telemetry-fields"; version: 1; minimum: 1; maximum: 512 };
  selection: {
    ids: string[];
    total_count: number;
    complete: boolean;
    unavailable_ids: string[];
    endpoint: Endpoint | null;
  };
  summary: {
    packet_count: number;
    selected_count: number;
    compatible_packet_count: number;
    selected_field_count: number;
  };
  packets: Page<Packet>;
  endpoints: Page<Endpoint>;
  detail: { packet_id: string; name: string; available: boolean; resources: Page<Resource> } | null;
  status: "unconfigured" | "configured" | "active" | "outdated" | "disabled";
  links: { self: string; manage: string };
};
export type SelectionInput = {
  expected_review: string;
  expected_configuration_version: number;
  input_id: "telemetry-fields";
  input_version: 1;
  catalog_revision_id: string;
  source_endpoint_ref: string;
  selected_packet_ids: string[];
};
export type PacketPort = {
  read: () => Promise<unknown>;
  save: (input: SelectionInput, key: string) => Promise<HostActionReceipt<unknown>>;
  navigate: (href: string) => void;
};
export type PacketReceipt = HostActionReceipt<{
  configurationId: string;
  applicationKey: "telemetry_decom";
  applicationVersion: 1;
  inputId: "telemetry-fields";
  inputVersion: 1;
  configurationVersion: number;
  enabled: boolean;
  selectedPacketIds: string[];
  bindingCount: number;
}>;
export const record = (x: unknown): x is Record<string, unknown> =>
  typeof x === "object" && x !== null && !Array.isArray(x);
export const id = (x: unknown): x is string =>
  typeof x === "string" && x.length > 0 && x.length <= 256 && !/[/?#\s]/.test(x);
const text = (x: unknown): x is string => typeof x === "string" && x.length <= 8192;
const integer = (x: unknown): x is number => Number.isSafeInteger(x) && (x as number) >= 0;
export const token = (x: unknown): x is string => typeof x === "string" && /^[a-f0-9]{64}$/.test(x);
export const ids = (x: unknown): x is string[] =>
  Array.isArray(x) && x.length <= 512 && x.every(id) && new Set(x).size === x.length;
export const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);
export const endpoint = (x: unknown): x is Endpoint => record(x) && id(x.id) && text(x.label);
function queryValue(key: string, value: string): boolean {
  if (["page", "endpoint_page", "resource_page"].includes(key))
    return /^[1-9][0-9]{0,5}$/.test(value) && Number(value) <= 100000;
  if (["q", "endpoint_q"].includes(key)) return new TextEncoder().encode(value).length <= 128;
  return key === "packet" && (value === "" || id(value));
}
function link(value: unknown, base: string): value is string {
  if (
    typeof value !== "string" ||
    !value.startsWith(base + "?") ||
    /[?#]/.test(value.slice(0, base.length)) ||
    value.includes("#") ||
    value.includes("\\") ||
    value.split("").some((char) => char.charCodeAt(0) <= 32)
  )
    return false;
  const query = new URLSearchParams(value.slice(base.length + 1));
  return (
    [...query].every(([key, value]) => queryValue(key, value)) &&
    new Set(query.keys()).size === [...query.keys()].length
  );
}
function page<T>(x: unknown, row: (x: unknown) => x is T, base: string): x is Page<T> {
  return (
    record(x) &&
    Array.isArray(x.items) &&
    x.items.length <= 25 &&
    x.items.every(row) &&
    integer(x.total_count) &&
    integer(x.page) &&
    x.page >= 1 &&
    x.page <= Math.max(1, Math.ceil(x.total_count / 25)) &&
    x.page_size === 25 &&
    x.items.length === Math.min(25, Math.max(0, x.total_count - (x.page - 1) * 25)) &&
    (x.previous_href === null ? x.page === 1 : x.page > 1 && link(x.previous_href, base)) &&
    (x.next_href === null
      ? x.page >= Math.max(1, Math.ceil(x.total_count / 25))
      : x.page < Math.ceil(x.total_count / 25) && link(x.next_href, base))
  );
}
export function admitPacketDocument(value: unknown, expected?: unknown): PacketDocument | null {
  if (!record(value) || value.contract_version !== 1 || !record(value.context)) return null;
  const c = value.context;
  if (![c.organization_id, c.mission_id, c.spacecraft_id, c.actor_id, c.installation_id].every(id))
    return null;
  if (
    expected !== undefined &&
    (!record(expected) ||
      expected.scope !== "spacecraft" ||
      expected.organizationId !== c.organization_id ||
      expected.missionId !== c.mission_id ||
      expected.spacecraftId !== c.spacecraft_id)
  )
    return null;
  const base = `/missions/${String(c.mission_id)}/spacecraft/${String(c.spacecraft_id)}/applications/telemetry_decom/packet_bindings`;
  if (!token(value.review_token) || !text(value.spacecraft_name) || !record(value.query))
    return null;
  const q = value.query;
  if (
    ![q.page, q.endpoint_page, q.resource_page].every((x) => integer(x) && x > 0 && x <= 100000) ||
    !["q", "endpoint_q", "packet"].every(
      (key) => typeof q[key] === "string" && queryValue(key, q[key]),
    )
  )
    return null;
  const config = value.configuration;
  if (
    config !== null &&
    (!record(config) ||
      !(config.id === null || id(config.id)) ||
      !integer(config.version) ||
      (config.id === null) !== (config.version === 0) ||
      !id(config.catalog_revision_id) ||
      !text(config.catalog_label) ||
      !integer(config.catalog_version) ||
      config.catalog_version < 1 ||
      typeof config.enabled !== "boolean")
  )
    return null;
  if (
    !record(value.input) ||
    value.input.id !== "telemetry-fields" ||
    value.input.version !== 1 ||
    value.input.minimum !== 1 ||
    value.input.maximum !== 512
  )
    return null;
  const s = value.selection,
    stats = value.summary;
  if (
    !record(s) ||
    !ids(s.ids) ||
    !ids(s.unavailable_ids) ||
    !s.unavailable_ids.every((x) => (s.ids as string[]).includes(x)) ||
    !integer(s.total_count) ||
    s.ids.length !== Math.min(s.total_count, 512) ||
    s.complete !== s.total_count <= 512 ||
    !(s.endpoint === null || endpoint(s.endpoint))
  )
    return null;
  if (
    !record(stats) ||
    ![
      stats.packet_count,
      stats.selected_count,
      stats.compatible_packet_count,
      stats.selected_field_count,
    ].every(integer) ||
    stats.selected_count !== s.total_count ||
    (stats.compatible_packet_count as number) > (stats.packet_count as number)
  )
    return null;
  const packet = (p: unknown): p is Packet =>
    record(p) &&
    id(p.id) &&
    text(p.name) &&
    integer(p.apid) &&
    p.apid <= 2047 &&
    integer(p.field_count) &&
    integer(p.compatible_field_count) &&
    p.compatible_field_count <= p.field_count &&
    p.selectable === p.compatible_field_count > 0 &&
    link(p.detail_href, base);
  if (!page(value.packets, packet, base) || !page(value.endpoints, endpoint, base)) return null;
  if (
    new Set(value.packets.items.map((x) => x.id)).size !== value.packets.items.length ||
    new Set(value.endpoints.items.map((x) => x.id)).size !== value.endpoints.items.length
  )
    return null;
  const detail = value.detail;
  const resource = (r: unknown): r is Resource =>
    record(r) &&
    id(r.id) &&
    text(r.path) &&
    text(r.type) &&
    (r.size_bits === null || integer(r.size_bits)) &&
    typeof r.compatible === "boolean";
  if (
    detail !== null &&
    (!record(detail) ||
      !id(detail.packet_id) ||
      !text(detail.name) ||
      typeof detail.available !== "boolean" ||
      !page(detail.resources, resource, base))
  )
    return null;
  if (
    !["unconfigured", "configured", "active", "outdated", "disabled"].includes(
      value.status as string,
    ) ||
    !record(value.links) ||
    value.links.self !== base ||
    value.links.manage !== base.replace(/packet_bindings$/, "manage")
  )
    return null;
  // Only the declared semantic document reaches feature state; transport extras are not props.
  return Object.fromEntries(
    [
      "contract_version",
      "context",
      "spacecraft_name",
      "review_token",
      "query",
      "configuration",
      "input",
      "selection",
      "summary",
      "packets",
      "endpoints",
      "detail",
      "status",
      "links",
    ].map((k) => [k, value[k]]),
  ) as PacketDocument;
}
export function validInput(value: unknown): value is SelectionInput {
  return (
    record(value) &&
    Object.keys(value).length === 7 &&
    Object.keys(value).every((k) =>
      [
        "expected_review",
        "expected_configuration_version",
        "input_id",
        "input_version",
        "catalog_revision_id",
        "source_endpoint_ref",
        "selected_packet_ids",
      ].includes(k),
    ) &&
    token(value.expected_review) &&
    integer(value.expected_configuration_version) &&
    value.input_id === "telemetry-fields" &&
    value.input_version === 1 &&
    id(value.catalog_revision_id) &&
    id(value.source_endpoint_ref) &&
    ids(value.selected_packet_ids) &&
    value.selected_packet_ids.length >= 1
  );
}
export function admitReceipt(value: unknown, input: SelectionInput): PacketReceipt | null {
  if (
    !record(value) ||
    !id(value.receiptId) ||
    typeof value.completedAt !== "string" ||
    !Number.isFinite(Date.parse(value.completedAt)) ||
    !record(value.result)
  )
    return null;
  const r = value.result;
  if (
    !id(r.configurationId) ||
    r.applicationKey !== "telemetry_decom" ||
    r.applicationVersion !== 1 ||
    r.inputId !== input.input_id ||
    r.inputVersion !== 1 ||
    !integer(r.configurationVersion) ||
    r.configurationVersion < 1 ||
    typeof r.enabled !== "boolean" ||
    !ids(r.selectedPacketIds) ||
    r.bindingCount !== r.selectedPacketIds.length ||
    !same([...r.selectedPacketIds].sort(), [...input.selected_packet_ids].sort())
  )
    return null;
  return {
    receiptId: value.receiptId,
    completedAt: value.completedAt,
    result: {
      configurationId: r.configurationId,
      applicationKey: r.applicationKey,
      applicationVersion: r.applicationVersion,
      inputId: r.inputId,
      inputVersion: r.inputVersion,
      configurationVersion: r.configurationVersion,
      enabled: r.enabled,
      selectedPacketIds: [...r.selectedPacketIds],
      bindingCount: r.selectedPacketIds.length,
    },
  };
}
