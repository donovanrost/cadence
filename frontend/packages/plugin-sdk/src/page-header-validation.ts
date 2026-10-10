import type { IconName } from "@cadence/ui/icons";
import type { Tone } from "@cadence/ui/tones";
import type { Href, Layer } from "./routes";
import type { HeaderStatus, MenuItem, PageAction } from "./page-header";

/** A header the host has admitted; what the host renderer draws. */
export type AdmittedHeader = {
  title?: string;
  identifier?: string;
  status?: HeaderStatus;
  description?: string;
  facts?: readonly string[];
  primary?: PageAction;
  actions?: readonly PageAction[];
  more?: readonly MenuItem[];
  refresh?: { run: () => void | Promise<void>; pending: boolean };
};

/**
 * The host's admission of a page header. Pages are built separately from the
 * host, so their header is decoded at the boundary like any other page data.
 */
const fail = (why: string): never => {
  throw new Error(`Invalid page header: ${why}`);
};
const record = (value: unknown, what: string): Record<string, unknown> =>
  value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : fail(what);
const only = (r: Record<string, unknown>, keys: readonly string[], what: string) => {
  for (const key of Object.keys(r))
    if (!keys.includes(key) && r[key] !== undefined) fail(`${what}.${key}`);
  return r;
};
const text = (value: unknown, max: number, what: string): string =>
  typeof value === "string" && value.trim() !== "" && value.length <= max ? value : fail(what);
const optional = <T>(value: unknown, read: (v: unknown) => T): T | undefined =>
  value === undefined ? undefined : read(value);
const tones: readonly Tone[] = ["info", "success", "warning", "error"];

function icon(value: unknown): IconName {
  return typeof value === "string" && /^hero-[a-z0-9-]+$/.test(value)
    ? (value as IconName)
    : fail("icon");
}
function link(value: unknown): Href {
  return typeof value === "string" && value.startsWith("/") && !value.startsWith("//")
    ? (value as Href)
    : fail("href");
}

function base(r: Record<string, unknown>) {
  return {
    id: text(r.id, 64, "action id"),
    label: text(r.label, 40, "action label"),
    ...(r.icon === undefined ? {} : { icon: icon(r.icon) }),
    ...(r.disabled === undefined ? {} : { disabled: r.disabled === true }),
  };
}

function menuItem(value: unknown): MenuItem {
  const r = only(
    record(value, "menu item"),
    ["id", "label", "icon", "disabled", "href", "run", "tone"],
    "menu item",
  );
  const tone =
    r.tone === undefined ? {} : r.tone === "danger" ? { tone: "danger" as const } : fail("tone");
  if (typeof r.run === "function") return { ...base(r), ...tone, run: r.run as () => void };
  return { ...base(r), ...tone, href: link(r.href) };
}

function action(value: unknown): PageAction {
  const r = only(
    record(value, "action"),
    ["id", "label", "icon", "disabled", "href", "run", "menu"],
    "action",
  );
  if (Array.isArray(r.menu)) {
    if (r.menu.length === 0 || r.menu.length > 12) fail("menu");
    return { ...base(r), menu: r.menu.map(menuItem) };
  }
  if (typeof r.run === "function") return { ...base(r), run: r.run as () => void };
  return { ...base(r), href: link(r.href) };
}

function list<T>(value: unknown, max: number, read: (v: unknown) => T, what: string): T[] {
  return Array.isArray(value) && value.length <= max ? value.map(read) : fail(what);
}

/** What a header may contain on each layer; mirrors the Ops and management types. */
const layers = {
  ops: { keys: ["refresh"], actions: 3 },
  management: { keys: ["identifier"], actions: 2 },
} as const;

/**
 * Decodes a page's header for its route's policy: `resource` routes must name
 * their resource, others must not, and each layer admits only its own fields.
 */
export function readPageHeader(
  value: unknown,
  policy: { kind: "collection" | "resource"; layer: Layer },
): AdmittedHeader {
  const { kind, layer } = policy;
  const r = only(
    record(value, "header"),
    [
      "title",
      "status",
      "description",
      "facts",
      "primary",
      "actions",
      "more",
      ...layers[layer].keys,
    ],
    `${layer} header`,
  );
  const common = {
    ...(r.description === undefined
      ? {}
      : { description: text(r.description, 240, "description") }),
    ...(r.facts === undefined
      ? {}
      : { facts: list(r.facts, 4, (v) => text(v, 60, "fact"), "facts") }),
    ...(r.primary === undefined ? {} : { primary: action(r.primary) }),
    ...(r.actions === undefined
      ? {}
      : { actions: list(r.actions, layers[layer].actions, action, "actions") }),
    ...(r.more === undefined ? {} : { more: list(r.more, 12, menuItem, "more") }),
    ...(r.refresh === undefined ? {} : { refresh: refresh(r.refresh) }),
  };
  const ids = [common.primary, ...(common.actions ?? []), ...(common.more ?? [])].flatMap((a) =>
    a ? [a.id] : [],
  );
  if (new Set(ids).size !== ids.length) fail("duplicate action id");
  if (kind === "collection") {
    if (r.title !== undefined || r.status !== undefined || r.identifier !== undefined)
      fail("collection pages take the route title");
    return common;
  }
  const status = optional(r.status, (v) => {
    const s = only(record(v, "status"), ["tone", "label"], "status");
    const tone = tones.find((t) => t === s.tone) ?? fail("status tone");
    return { tone, label: text(s.label, 24, "status label") };
  });
  return {
    ...common,
    title: text(r.title, 120, "title"),
    ...(r.identifier === undefined ? {} : { identifier: text(r.identifier, 120, "identifier") }),
    ...(status ? { status } : {}),
  };
}

function refresh(value: unknown) {
  const r = only(record(value, "refresh"), ["run", "pending"], "refresh");
  if (typeof r.run !== "function") fail("refresh.run");
  return { run: r.run as () => void, pending: r.pending === true };
}
