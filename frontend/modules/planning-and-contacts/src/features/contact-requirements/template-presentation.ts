import type {
  FormField,
  OpsContactRequirementTemplateProps,
  TemplateValues,
} from "./OpsContactRequirementTemplate.contracts";
import type { TemplateModel, TemplateReference } from "./templates";
import type { SpacecraftChoices } from "./declaration";
import { requirementSegment } from "./requirement-directory";
export function templatePresentation(
  m: TemplateModel,
  v: TemplateValues,
  selected?: SpacecraftChoices["entries"][number],
): OpsContactRequirementTemplateProps {
  const choices = [...m.spacecraft.entries];
  if (selected && !choices.some((c) => c.id === selected.id)) choices.unshift(selected);
  const field = (
    key: keyof TemplateValues,
    id: string,
    label: string,
    type: FormField["type"],
    extra: Partial<FormField> = {},
  ): FormField => ({
    id: `template-${id}`,
    name: `template[${key}]`,
    label,
    type,
    required: false,
    value: v[key],
    min: null,
    step: null,
    options: [],
    errors: [],
    ...extra,
  });
  const options = (pairs: readonly (readonly [string, string])[]) =>
    pairs.map(([value, label]) => ({ value, label }));
  const lifecycle = (ref: TemplateReference) => {
    const id = requirementSegment(ref.template_id);
    return {
      pause:
        ref.lifecycle_state === "active"
          ? { id: `pause-template-${id}`, label: "Pause", class: "btn btn-ghost btn-xs" }
          : null,
      activate:
        ref.lifecycle_state === "paused"
          ? {
              id: `activate-template-${id}`,
              label: "Activate",
              class: "btn btn-ghost btn-xs text-success",
            }
          : null,
      close:
        ref.lifecycle_state !== "closed"
          ? { id: `close-template-${id}`, label: "Close", class: "btn btn-ghost btn-xs text-error" }
          : null,
    };
  };
  const duration = (s: number) => (s % 60 === 0 ? `${s / 60} min` : `${s} sec`);
  return {
    page: {
      id: "ops-requirement-templates-page",
      back: {
        href: `/missions/${requirementSegment(m.context.mission_id)}/ops/planning`,
        icon: "hero-arrow-left",
        label: "Fleet planning",
      },
      header: {
        eyebrow: "Recurring demand definition",
        title: "Requirement Templates",
        copy: "Define a UTC recurrence once. Each due occurrence materializes exactly one ordinary Contact Requirement with immutable provenance.",
      },
    },
    ledger: {
      eyebrow: "Template ledger",
      copy: "Lifecycle and current immutable schedule version.",
      count: m.templates.entries.length,
      count_label: `${m.templates.entries.length}${m.templates.more ? "+" : ""} shown`,
      list_id: "requirement-templates",
      stream_empty_id: "requirement-templates-stream-empty",
      empty:
        m.templates.entries.length === 0
          ? {
              id: "requirement-templates-empty",
              icon: "hero-arrow-path-rounded-square",
              title:
                m.templates.page === 1 ? "No recurring contact needs" : "No templates on this page",
              copy: "Use a template for routine downlinks. One-off operational needs remain ordinary Requirements.",
            }
          : null,
    },
    authorization: {
      organization_admin: m.can_manage,
      admin_required: m.can_manage
        ? null
        : {
            id: "requirement-template-admin-required",
            copy: "Administrator authority is required to manage recurring demand.",
          },
    },
    templates: m.templates.entries.map((e) => ({
      id: e.reference.template_id,
      __dom_id: `requirement-template-${requirementSegment(e.reference.template_id)}`,
      lifecycle: {
        state: e.reference.lifecycle_state,
        class: `border px-1.5 py-0.5 font-mono text-[0.58rem] uppercase ${e.reference.lifecycle_state === "active" ? "border-success/35 bg-success/10 text-success" : e.reference.lifecycle_state === "paused" ? "border-warning/35 bg-warning/10 text-warning" : "border-base-300 text-base-content/45"}`,
      },
      version_label: `v${e.reference.version}`,
      title: `${e.spacecraft_id} · ${e.contact_intent.replaceAll("_", " ")}`,
      schedule: `${e.schedule.type === "daily" ? `Daily at ${e.schedule.time_utc} UTC` : `Every ${duration(e.schedule.interval_seconds)}`} · ${duration(e.schedule.window_duration_seconds)} window`,
      content_sha256: e.reference.content_sha256,
      ...(m.can_manage ? { actions: lifecycle(e.reference) } : {}),
    })),
    template_form: !m.can_manage
      ? null
      : {
          panel_id: "requirement-template-editor",
          id: "requirement-template-form",
          header: {
            eyebrow: "Create recurring need",
            copy: "UTC schedule → ordinary Requirements",
          },
          fields: {
            spacecraft_id: field("spacecraft_id", "spacecraft", "Spacecraft", "select", {
              required: true,
              options: [
                { value: "", label: "Choose spacecraft" },
                ...choices.map((c) => ({ value: c.id, label: c.name })),
              ],
            }),
            schedule_type: field("schedule_type", "schedule-type", "Schedule", "select", {
              options: options([
                ["fixed_interval", "Fixed interval"],
                ["daily", "Daily UTC"],
              ]),
            }),
            anchor_at: field("anchor_at", "anchor-at", "Starts (UTC)", "datetime-local", {
              required: true,
              step: "1",
            }),
            interval_minutes: field(
              "interval_minutes",
              "interval-minutes",
              "Every minutes",
              "number",
              { required: true, min: 1 },
            ),
            time_utc: field("time_utc", "time-utc", "Daily at UTC", "time", {
              required: true,
              step: "1",
            }),
            window_offset_minutes: field(
              "window_offset_minutes",
              "window-offset",
              "Window offset minutes",
              "number",
              { required: true },
            ),
            window_duration_minutes: field(
              "window_duration_minutes",
              "window-duration",
              "Window duration minutes",
              "number",
              { required: true, min: 1 },
            ),
            contact_intent: field("contact_intent", "contact-intent", "Contact intent", "text", {
              required: true,
            }),
            success_measure: field(
              "success_measure",
              "success-measure",
              "Success measure",
              "select",
              {
                options: options([
                  ["minimum_duration", "Minimum duration"],
                  ["minimum_data_volume", "Minimum data volume"],
                  ["contact_count", "Contact count"],
                  ["any_contact", "Any eligible contact"],
                ]),
              },
            ),
            minimum_duration_seconds: field(
              "minimum_duration_seconds",
              "minimum-duration",
              "Minimum seconds",
              "number",
              { min: 1 },
            ),
            preferred_duration_seconds: field(
              "preferred_duration_seconds",
              "preferred-duration",
              "Preferred seconds",
              "number",
              { min: 1 },
            ),
            minimum_data_volume_bytes: field(
              "minimum_data_volume_bytes",
              "minimum-data-volume",
              "Minimum bytes",
              "number",
              { min: 1 },
            ),
            contact_count: field("contact_count", "contact-count", "Contact count", "number", {
              required: true,
              min: 1,
            }),
            minimum_separation_seconds: field(
              "minimum_separation_seconds",
              "minimum-separation",
              "Separation seconds",
              "number",
              { required: true, min: 0 },
            ),
            priority: field("priority", "priority", "Priority", "select", {
              options: options([
                ["critical", "Critical"],
                ["high", "High"],
                ["routine", "Routine"],
              ]),
            }),
            approval_mode: field("approval_mode", "approval-mode", "Approval", "select", {
              options: options([
                ["manual", "Manual"],
                ["bounded_automatic", "Bounded automatic"],
              ]),
            }),
            maximum_occurrences_per_run: field(
              "maximum_occurrences_per_run",
              "max-occurrences",
              "Max per run",
              "number",
              { required: true, min: 1 },
            ),
            maximum_lookback_hours: field(
              "maximum_lookback_hours",
              "max-lookback",
              "Max lookback hours",
              "number",
              { required: true, min: 0 },
            ),
            rationale: field("rationale", "rationale", "Operational rationale", "textarea", {
              required: true,
            }),
          },
          outcome_details: {
            id: "requirement-template-outcome-details",
            summary: "Duration and separation preferences",
          },
          catchup_details: { id: "requirement-template-catchup", summary: "Catch-up guardrails" },
          submit: { id: "create-requirement-template", label: "Activate template" },
        },
  };
}
