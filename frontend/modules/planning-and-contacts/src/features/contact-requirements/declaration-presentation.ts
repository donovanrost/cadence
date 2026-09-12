import type {
  ContactRequirementValues,
  FormField,
  OpsContactRequirementNewProps,
} from "./OpsContactRequirementNew.contracts";
import type { DeclarationModel, SpacecraftChoices } from "./declaration";
import { requirementSegment } from "./requirement-directory";
export function declarationPresentation(
  model: DeclarationModel,
  values: ContactRequirementValues,
  error = "",
  selected?: SpacecraftChoices["entries"][number],
): OpsContactRequirementNewProps {
  const field = (
    key: keyof ContactRequirementValues,
    id: string,
    label: string,
    type: FormField["type"],
    extra: Partial<FormField> = {},
  ): FormField => ({
    id: `requirement-${id}`,
    name: `contact_requirement[${key}]`,
    label,
    type,
    required: false,
    value: values[key],
    ...extra,
  });
  const choices = [...model.spacecraft.entries];
  if (selected && !choices.some((c) => c.id === selected.id)) choices.unshift(selected);
  const options = (pairs: string[][]) => pairs.map(([value, label]) => ({ value, label }));
  const href = `/missions/${requirementSegment(model.context.mission_id)}/ops/requirements`;
  return {
    page: {
      id: "ops-contact-requirement-new-page",
      eyebrow: "Need / outcome-first declaration",
      heading: "What does the mission need?",
      description:
        "Describe success and the acceptable horizon. Planning will resolve eligible providers, stations, and routes.",
    },
    journey: {
      outcome: {
        id: "contact-requirement-outcome-section",
        step: "01",
        title: "Mission outcome",
        copy: "The operator-readable reason this contact must exist.",
      },
      horizon: {
        id: "contact-requirement-horizon-section",
        step: "02",
        title: "Acceptable horizon",
        copy: "All times are coordinated universal time.",
      },
      advanced: {
        id: "requirement-advanced-constraints",
        title: "Advanced constraints",
        copy: "Optional provider and station boundaries",
      },
      rationale: { id: "contact-requirement-rationale-section" },
      progressive: {
        minimum_data_volume: {
          id: "requirement-minimum-data-volume-section",
          visible: values.success_measure === "minimum_data_volume",
          visible_for: ["minimum_data_volume"],
        },
        minimum_duration: {
          id: "requirement-minimum-duration-section",
          visible: ["minimum_duration", "minimum_data_volume"].includes(values.success_measure),
          visible_for: ["minimum_duration", "minimum_data_volume"],
        },
      },
    },
    form: {
      id: "contact-requirement-form",
      error: error ? { id: "contact-requirement-form-error", message: error } : null,
      fields: {
        spacecraft_id: field("spacecraft_id", "spacecraft", "Spacecraft", "select", {
          required: true,
          options: choices.map((c) => ({ value: c.id, label: c.name })),
        }),
        contact_intent: field("contact_intent", "intent", "Contact intent", "select", {
          options: options([
            ["payload_downlink", "Payload downlink"],
            ["health_and_safety", "Health and safety"],
            ["ttc_maintenance", "TT&C maintenance"],
            ["commissioning", "Commissioning"],
          ]),
        }),
        success_measure: field("success_measure", "success-measure", "Success means", "select", {
          options: options([
            ["minimum_data_volume", "Minimum data volume"],
            ["minimum_duration", "Minimum contact duration"],
            ["contact_count", "Number of contacts"],
            ["any_contact", "Any eligible contact"],
          ]),
        }),
        priority: field("priority", "priority", "Operational priority", "select", {
          options: options([
            ["routine", "Routine"],
            ["high", "High"],
            ["critical", "Critical"],
          ]),
        }),
        earliest_start: field(
          "earliest_start",
          "earliest-start",
          "Earliest start (UTC)",
          "datetime-local",
          { required: true },
        ),
        latest_end: field("latest_end", "latest-end", "Latest end (UTC)", "datetime-local", {
          required: true,
        }),
        minimum_data_volume_bytes: field(
          "minimum_data_volume_bytes",
          "minimum-data-volume",
          "Minimum data volume (bytes)",
          "number",
          { min: "1" },
        ),
        minimum_duration_seconds: field(
          "minimum_duration_seconds",
          "minimum-duration",
          "Minimum window duration (seconds)",
          "number",
          { min: "1" },
        ),
        preferred_duration_seconds: field(
          "preferred_duration_seconds",
          "preferred-duration",
          "Preferred window duration (seconds)",
          "number",
          { min: "1" },
        ),
        contact_count: field("contact_count", "contact-count", "Required contact count", "number", {
          min: "1",
        }),
        minimum_separation_seconds: field(
          "minimum_separation_seconds",
          "minimum-separation",
          "Minimum separation (seconds)",
          "number",
          { min: "0" },
        ),
        allowed_providers: field(
          "allowed_providers",
          "allowed-providers",
          "Allowed provider IDs",
          "text",
          { placeholder: "provider-a, provider-b" },
        ),
        excluded_providers: field(
          "excluded_providers",
          "excluded-providers",
          "Excluded provider IDs",
          "text",
          { placeholder: "provider-c" },
        ),
        allowed_stations: field(
          "allowed_stations",
          "allowed-stations",
          "Allowed station refs",
          "text",
          { placeholder: "station-a, station-b" },
        ),
        excluded_stations: field(
          "excluded_stations",
          "excluded-stations",
          "Excluded station refs",
          "text",
          { placeholder: "station-c" },
        ),
        rationale: field("rationale", "rationale", "Operator rationale", "textarea", {
          required: true,
          placeholder: "Why this outcome and horizon are operationally important",
          maxlength: "2000",
        }),
      },
    },
    actions: {
      back: {
        id: "contact-requirements-back-link",
        label: "Requirements",
        href,
        icon: "hero-arrow-left",
      },
      cancel: { id: "cancel-contact-requirement", label: "Cancel", href },
      submit: { id: "save-contact-requirement", label: "Declare need" },
    },
  };
}
