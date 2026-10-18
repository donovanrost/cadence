export type StatusTone = "ready" | "attention" | "blocked" | "info";
export type PreflightState = "ready" | "attention" | "blocked";
export type DiagnosticSeverity = "error" | "warning" | "info";
export type ButtonVariant = "primary" | "secondary" | "danger";

type Breadcrumb = {
  id: string;
  label: string;
  href: string | null;
};

type Page = {
  id: string;
  title: string;
  subtitle: string;
  breadcrumbs: Breadcrumb[];
};

type Card = {
  id: string;
};

type Status = {
  state: string;
  tone: StatusTone;
  label: string;
  description: string;
  saved_label: string | null;
};

type Revision = {
  form_id: string;
  field: {
    id: string;
    name: string;
    label: string;
    value: string;
    options: { label: string; value: string }[];
  };
  action: {
    id: string;
    label: string;
  };
};

type NoRevisions = {
  message: string;
  action: {
    label: string;
    href: string;
  };
};

type PacketHandoff = {
  id: string;
  label: string;
  selection_count: number;
  row_count: number;
  summary_suffix: string;
  detail: string;
  action: {
    id: string;
    label: string;
    href: string;
  };
};

type PreviewStat = {
  id: string;
  label: string;
  value: number;
};

type DiagnosticItem = {
  id: string;
  diagnostic_id: string;
  code: string;
  severity: DiagnosticSeverity;
  title: string;
  detail: string;
  value: string | null;
};

type Diagnostics = {
  id: string;
  items_id: string;
  role: "alert" | "status";
  severity: DiagnosticSeverity;
  count: number;
  total_count: number;
  count_label: string;
  label: string;
  title: string;
  description: string;
  items: DiagnosticItem[];
};

type Preview = {
  id: string;
  label: string;
  empty_message: string | null;
  stats: PreviewStat[];
  diagnostics: Diagnostics | null;
};

type PreflightCheck = {
  id: string;
  check_id: string;
  category: string;
  state: PreflightState;
  title: string;
  detail: string;
  value: string | null;
};

type Preflight = {
  id: string;
  checks_id: string;
  state: PreflightState;
  activation_ready: boolean;
  check_count: number;
  application_version: number;
  summary: string;
  label: string;
  checks: PreflightCheck[];
};

type PendingActivation = {
  id: string;
  activation_request_id: string;
  message_before: string;
  message_after: string;
};

type Confirmation = {
  title: string;
  message: string;
  confirm_label: string;
  tone: "attention" | "danger";
  prompt: string;
};

export type LifecycleAction = {
  id: string;
  action_id: string;
  event: "enable" | "disable";
  label: string;
  variant: ButtonVariant;
  effect: string;
  execution: string;
  confirmation: Confirmation | null;
  disabled: boolean;
};

type LifecycleActions = {
  empty_message: string | null;
  disable: LifecycleAction | null;
  enable: LifecycleAction | null;
};

type ConfigurationReview = {
  configuration_token: string;
  mission_token: string | null;
  total_count: number;
  truncated: boolean;
  configurations: {
    spacecraft_id: string;
    spacecraft_name: string | null;
    source_endpoint_name: string | null;
    configuration_version: number;
    catalog_revision_id: string;
    source_endpoint_id: string;
    handled_apids: number[];
    enabled: boolean;
  }[];
  packet_inputs: {
    id: string;
    spacecraft_id: string;
    spacecraft_name: string | null;
    input_id: string;
    configuration_version: number;
    enabled: boolean;
    packet_count: number;
  }[];
};

export type ConfigurationPresentation = {
  contract_version: 1;
  review: ConfigurationReview;
  context: { organization_id: string; mission_id: string; spacecraft_id: string };
  configuration: {
    catalog_revision_id: string;
    source_endpoint_id: string;
    configuration_version: number;
    enabled: boolean;
    handled_apids: number[];
  } | null;
  page: Page;
  card: Card;
  status: Status;
  revision: Revision | null;
  no_revisions: NoRevisions | null;
  packet_handoff: PacketHandoff | null;
  preview: Preview | null;
  preflight: Preflight;
  pending_activation: PendingActivation | null;
  lifecycle_actions: LifecycleActions;
};

// The feature owns admission. Delivery packages and the host do not interpret these fields.
type Rule = (value: unknown) => boolean;
const record = (x: unknown): x is Record<string, unknown> =>
  typeof x === "object" && x !== null && !Array.isArray(x);
const text: Rule = (x) => typeof x === "string" && x.length <= 8192;
const id: Rule = (x) => typeof x === "string" && x.length > 0 && x.length <= 1024;
const integer: Rule = (x) => Number.isSafeInteger(x) && (x as number) >= 0;
const positive: Rule = (x) => integer(x) && (x as number) > 0;
const boolean: Rule = (x) => typeof x === "boolean";
const values =
  (...allowed: unknown[]): Rule =>
  (x) =>
    allowed.includes(x);
const nullable =
  (rule: Rule): Rule =>
  (x) =>
    x === null || rule(x);
const object =
  (fields: Record<string, Rule>): Rule =>
  (x) =>
    record(x) && Object.entries(fields).every(([key, rule]) => rule(x[key]));
const list =
  (rule: Rule, max = 4096): Rule =>
  (x) =>
    Array.isArray(x) && x.length <= max && x.every(rule);
const href: Rule = (x) =>
  typeof x === "string" && /^\/missions\/[^/]+(?:\/[^\s?#\\]+)*$/.test(x) && !/%(?:2f|5c)/i.test(x);
const tone = values("ready", "attention", "blocked", "info");
const state = values("ready", "attention", "blocked");
const severity = values("error", "warning", "info");
const action = object({
  id,
  action_id: id,
  event: values("enable", "disable"),
  label: text,
  variant: values("primary", "secondary", "danger"),
  effect: id,
  execution: id,
  disabled: boolean,
  confirmation: nullable(
    object({
      title: text,
      message: text,
      confirm_label: text,
      tone: values("attention", "danger"),
      prompt: text,
    }),
  ),
});
const reviewToken: Rule = (x) => typeof x === "string" && /^[a-f0-9]{64}$/.test(x);
const fields = {
  review: object({
    configuration_token: reviewToken,
    mission_token: nullable(reviewToken),
    total_count: integer,
    truncated: boolean,
    configurations: list(
      object({
        spacecraft_id: id,
        spacecraft_name: nullable(text),
        source_endpoint_name: nullable(text),
        configuration_version: positive,
        catalog_revision_id: id,
        source_endpoint_id: id,
        handled_apids: list((x) => integer(x) && (x as number) <= 2047, 2048),
        enabled: boolean,
      }),
      200,
    ),
    packet_inputs: list(
      object({
        id,
        spacecraft_id: id,
        spacecraft_name: nullable(text),
        input_id: id,
        configuration_version: positive,
        enabled: boolean,
        packet_count: integer,
      }),
      200,
    ),
  }),
  contract_version: values(1),
  context: object({ organization_id: id, mission_id: id, spacecraft_id: id }),
  configuration: nullable(
    object({
      catalog_revision_id: id,
      source_endpoint_id: id,
      configuration_version: positive,
      enabled: boolean,
      handled_apids: list((x) => integer(x) && (x as number) <= 2047, 2048),
    }),
  ),
  page: object({
    id,
    title: text,
    subtitle: text,
    breadcrumbs: list(object({ id, label: text, href: nullable(href) }), 10),
  }),
  card: object({ id }),
  status: object({
    state: values("applied", "configured", "outdated", "disabled", "not_configured"),
    tone,
    label: text,
    description: text,
    saved_label: nullable(text),
  }),
  revision: nullable(
    object({
      form_id: id,
      field: object({
        id,
        name: values("catalog_revision_id"),
        label: text,
        value: text,
        options: list(object({ label: text, value: id })),
      }),
      action: object({ id, label: text }),
    }),
  ),
  no_revisions: nullable(object({ message: text, action: object({ label: text, href }) })),
  packet_handoff: nullable(
    object({
      id,
      label: text,
      selection_count: integer,
      row_count: integer,
      summary_suffix: text,
      detail: text,
      action: object({ id, label: text, href }),
    }),
  ),
  preview: nullable(
    object({
      id,
      label: text,
      empty_message: nullable(text),
      stats: list(object({ id, label: text, value: integer }), 10),
      diagnostics: nullable(
        object({
          id,
          items_id: id,
          role: values("alert", "status"),
          severity,
          count: integer,
          total_count: integer,
          count_label: text,
          label: text,
          title: text,
          description: text,
          items: list(
            object({
              id,
              diagnostic_id: id,
              code: id,
              severity,
              title: text,
              detail: text,
              value: nullable(text),
            }),
            100,
          ),
        }),
      ),
    }),
  ),
  preflight: object({
    id,
    checks_id: id,
    state,
    activation_ready: boolean,
    check_count: integer,
    application_version: values(1),
    summary: text,
    label: text,
    checks: list(
      object({
        id,
        check_id: id,
        category: id,
        state,
        title: text,
        detail: text,
        value: nullable(text),
      }),
      100,
    ),
  }),
  pending_activation: nullable(
    object({ id, activation_request_id: id, message_before: text, message_after: text }),
  ),
  lifecycle_actions: object({
    empty_message: nullable(text),
    disable: nullable(action),
    enable: nullable(action),
  }),
};
const shape = object(fields);

export function admitConfiguration(
  value: unknown,
  expected?: unknown,
): ConfigurationPresentation | null {
  if (!shape(value)) return null;
  const p = value as ConfigurationPresentation;
  const review = p.review;
  const shown = review.configurations.length + review.packet_inputs.length;
  if (
    shown !== Math.min(review.total_count, 200) ||
    review.truncated !== review.total_count > 200 ||
    (review.mission_token === null) !== review.truncated ||
    new Set(review.configurations.map((c) => c.spacecraft_id)).size !==
      review.configurations.length ||
    new Set(review.packet_inputs.map((p) => p.id)).size !== review.packet_inputs.length
  )
    return null;
  if (
    expected !== undefined &&
    (!record(expected) ||
      expected.scope !== "spacecraft" ||
      expected.organizationId !== p.context.organization_id ||
      expected.missionId !== p.context.mission_id ||
      expected.spacecraftId !== p.context.spacecraft_id)
  )
    return null;
  const base = `/missions/${p.context.mission_id}`;
  if (
    p.page.breadcrumbs.some(
      (b) => b.href !== null && b.href !== base && !b.href.startsWith(base + "/"),
    )
  )
    return null;
  if (p.no_revisions && p.no_revisions.action.href !== base + "/catalog") return null;
  if (
    p.packet_handoff &&
    p.packet_handoff.action.href !==
      `${base}/spacecraft/${p.context.spacecraft_id}/applications/telemetry_decom/packet_bindings`
  )
    return null;
  if (p.configuration && p.revision?.field.value !== p.configuration.catalog_revision_id)
    return null;
  if (!p.configuration && p.revision && p.revision.field.value !== "") return null;
  if ((p.revision === null) !== (p.no_revisions !== null)) return null;
  const checks = p.preflight.checks;
  if (
    !checks.length ||
    p.preflight.check_count !== checks.length ||
    new Set(checks.map((c) => c.check_id)).size !== checks.length
  )
    return null;
  const overall = checks.some((c) => c.state === "blocked")
    ? "blocked"
    : checks.some((c) => c.state === "attention")
      ? "attention"
      : "ready";
  if (p.preflight.state !== overall || p.preflight.activation_ready !== (overall !== "blocked"))
    return null;
  const revision = p.revision;
  if (
    revision &&
    (new Set(revision.field.options.map((o) => o.value)).size !== revision.field.options.length ||
      (revision.field.value !== "" &&
        !revision.field.options.some((o) => o.value === revision.field.value)))
  )
    return null;
  if (
    p.packet_handoff &&
    (p.packet_handoff.selection_count > p.packet_handoff.row_count ||
      p.packet_handoff.selection_count !== p.configuration?.handled_apids.length)
  )
    return null;
  const diagnostics = p.preview?.diagnostics;
  if (
    diagnostics &&
    (diagnostics.count !== diagnostics.items.length || diagnostics.count > diagnostics.total_count)
  )
    return null;
  if (
    p.lifecycle_actions.disable &&
    (p.lifecycle_actions.disable.action_id !== "disable" ||
      p.lifecycle_actions.disable.event !== "disable" ||
      !p.configuration?.enabled)
  )
    return null;
  if (
    p.lifecycle_actions.enable &&
    (p.lifecycle_actions.enable.action_id !== "request_activation" ||
      p.lifecycle_actions.enable.event !== "enable" ||
      !p.configuration ||
      ((!p.preflight.activation_ready || p.pending_activation) &&
        !p.lifecycle_actions.enable.disabled))
  )
    return null;
  return Object.fromEntries(
    Object.keys(fields).map((key) => [key, (value as Record<string, unknown>)[key]]),
  ) as ConfigurationPresentation;
}
