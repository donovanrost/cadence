import type {
  InstallationSnapshot,
  MissionPresentation,
  SpacecraftPresentation,
} from "./contracts";

type Check = (value: unknown) => boolean;
const record = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);
const text: Check = (value) => typeof value === "string";
const bool: Check = (value) => typeof value === "boolean";
const positive: Check = (value) => Number.isSafeInteger(value) && Number(value) > 0;
const choice =
  (...values: unknown[]): Check =>
  (value) =>
    values.includes(value);
const nullable =
  (check: Check): Check =>
  (value) =>
    value === null || check(value);
const list =
  (check: Check): Check =>
  (value) =>
    Array.isArray(value) && value.length <= 10000 && value.every(check);
const shape =
  (fields: Record<string, Check>): Check =>
  (value) =>
    record(value) && Object.entries(fields).every(([key, check]) => check(value[key]));
const href: Check = (value) =>
  typeof value === "string" &&
  /^(?:#[^\\\s]*|\/missions(?:\/[^\\\s?#]*)?(?:\?[^\\\s#]*)?(?:#[^\\\s]*)?)$/.test(value);
const allowedAttrs: Record<string, Check> = {
  id: text,
  class: text,
  href,
  "aria-label": text,
  "aria-hidden": choice("true", "false"),
  "data-phx-link": choice("redirect", "patch"),
  "data-phx-link-state": choice("push", "replace"),
};
const attrs: Check = (value) =>
  record(value) &&
  Object.entries(value).every(
    ([key, item]) => Object.hasOwn(allowedAttrs, key) && (allowedAttrs[key]?.(item) ?? false),
  );
const element = shape({ attrs });
const label = shape({ attrs, text });
const breadcrumb: Check = (value) =>
  shape({ label: text, href: nullable(href) })(value) ||
  shape({ key: text, separator: nullable(label), link: nullable(label), current: nullable(label) })(
    value,
  );
const headerFields = {
  attrs,
  body: element,
  content: element,
  breadcrumbs: shape({ attrs, items: list(breadcrumb) }),
  title: label,
  subtitle: label,
};
const confirmation = nullable(
  shape({
    title: text,
    message: text,
    confirm_label: text,
    tone: choice("attention", "danger"),
    prompt: text,
  }),
);
const action = (event: string) =>
  nullable(
    shape({
      id: text,
      action_id: choice(event),
      label: text,
      variant: choice("primary", "secondary", "danger"),
      effect: choice("durable"),
      execution: choice("immediate"),
      confirmation,
    }),
  );
const application = shape({
  id: text,
  application_key: text,
  application_version: nullable(positive),
  display_name: text,
  description: text,
  lifecycle_state: nullable(text),
  installable: bool,
  manageable: bool,
  uninstallable: bool,
  scope_label: text,
  manage_path: href,
  status: shape({
    state: text,
    label: text,
    tone: choice("info", "ready", "attention", "blocked"),
    facts: list(shape({ id: text, label: text, value: nullable(text) })),
  }),
  install_action: action("install"),
  disable_action: action("disable"),
  uninstall_action: action("uninstall"),
  unavailable_message: nullable(text),
});
const profile: Check = (value) =>
  shape({
    kind: choice("missing"),
    id: text,
    label: text,
    title: text,
    description: text,
    action: shape({ label: text, path: href }),
  })(value) ||
  shape({
    kind: choice("pinned"),
    id: text,
    label: text,
    display_name: text,
    version: positive,
    status: shape({ tone: choice("ready", "attention"), label: text }),
  })(value);
const mission = shape({
  root: element,
  header: shape(headerFields),
  applications_component: shape({ attrs, props: shape({ applications: list(application) }) }),
});
const spacecraft = shape({
  root: element,
  header: shape({ ...headerFields, actions: shape({ attrs, readiness: label }) }),
  component: element,
  profile,
  applications: list(application),
});
export function assertMission(value: unknown): asserts value is MissionPresentation {
  if (!mission(value)) throw new Error("Invalid mission installation inventory.");
}
export function assertSpacecraft(value: unknown): asserts value is SpacecraftPresentation {
  if (!spacecraft(value)) throw new Error("Invalid spacecraft installation inventory.");
}
export function admitSnapshot(value: unknown, scope: string): InstallationSnapshot | null {
  if (!record(value) || value.version !== 1 || value.status !== "ready" || value.scope !== scope)
    return null;
  try {
    if (scope === "mission") {
      assertMission(value.data);
      return { version: 1, scope, status: "ready", data: value.data };
    }
    if (scope === "spacecraft") {
      assertSpacecraft(value.data);
      return { version: 1, scope, status: "ready", data: value.data };
    }
  } catch {
    /* The feature contains malformed snapshots without losing host navigation. */
  }
  return null;
}
