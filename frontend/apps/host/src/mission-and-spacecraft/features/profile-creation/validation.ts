import {
  assertShape,
  bool,
  choice,
  href,
  list,
  nullable,
  record,
  shape,
  text,
} from "../../shared/validation.ts";
import type { ProfileData, ProfileErrors } from "./contracts";
const field = (name: string, type: string) =>
  shape({
    id: text,
    name: choice("spacecraft_type[" + name + "]"),
    type: choice(type),
    label: text,
    required: bool,
    value: text,
  });
const section = shape({ id: text, number: text, title: text, description: nullable(text) });
const option = shape({ label: text, value: text });
const values = (value: unknown) => record(value) && Object.values(value).every(text);
const form = shape({
  page: shape({
    id: choice("spacecraft-profile-new-page"),
    title: text,
    subtitle: text,
    breadcrumbs: list(shape({ label: text, href: nullable(href) })),
  }),
  form: shape({
    id: text,
    sections: shape({
      identity: section,
      protocols: section,
      frame_parameters: section,
      applications: section,
    }),
    fields: shape({
      display_name: field("display_name", "text"),
      downlink_protocol: field("downlink_protocol", "select"),
      uplink_protocol: field("uplink_protocol", "select"),
      frame_size: field("frame_size", "number"),
      secondary_header_length: field("secondary_header_length", "number"),
      insert_zone_length: field("insert_zone_length", "number"),
      truncated_primary_header: field("truncated_primary_header", "select"),
      ocf_length: field("ocf_length", "select"),
      applications: shape({
        id: text,
        name: choice("spacecraft_type[applications]"),
        value: values,
      }),
    }),
    actions: shape({
      submit: shape({ id: text, label: text }),
      cancel: shape({ id: text, label: text, href }),
    }),
  }),
  options: shape({
    downlink_protocols: list(option),
    uplink_protocols: list(option),
    truncated_primary_headers: list(option),
    operational_control_fields: list(option),
    frame_fields: shape({
      secondary_header_length: list(choice("tm")),
      insert_zone_length: list(choice("aos")),
      truncated_primary_header: list(choice("uslp")),
    }),
  }),
  applications: list(
    shape({
      id: text,
      key: text,
      name: text,
      value: choice("1"),
      label: text,
      description: text,
      available: bool,
      availability_label: nullable(text),
    }),
  ),
});
export function assertProfileForm(value: unknown): void {
  assertShape(form, value);
  const data = value as ProfileData;
  const pairs = [
    ["downlink_protocol", "downlink_protocols", ["tm", "aos", "uslp"]],
    ["uplink_protocol", "uplink_protocols", ["tc", "uslp"]],
    ["truncated_primary_header", "truncated_primary_headers", ["false", "true"]],
    ["ocf_length", "operational_control_fields", ["0", "4"]],
  ] as const;
  for (const [field, options, allowed] of pairs) {
    const offered = data.options[options].map((option) => option.value);
    if (
      offered.length !== allowed.length ||
      !allowed.every((value) => offered.includes(value)) ||
      !offered.includes(data.form.fields[field].value)
    )
      throw new Error("Invalid protocol options.");
  }
  const keys = data.applications.map((application) => application.key);
  if (
    new Set(keys).size !== keys.length ||
    data.applications.some(
      (application) =>
        application.name !== "spacecraft_type[applications][" + application.key + "]",
    )
  )
    throw new Error("Invalid application options.");
  if (
    Object.entries(data.form.fields.applications.value).some(
      ([key, value]) =>
        value !== "1" ||
        !data.applications.some((application) => application.key === key && application.available),
    )
  )
    throw new Error("Invalid selected application.");
}
export function assertProfileResult(
  value: unknown,
): asserts value is { status: "ok" | "invalid"; errors: ProfileErrors } {
  if (
    !record(value) ||
    !["ok", "invalid"].includes(String(value.status)) ||
    !record(value.errors) ||
    !Object.entries(value.errors).every(
      ([field, messages]) =>
        [
          "display_name",
          "downlink_protocol",
          "uplink_protocol",
          "frame_size",
          "secondary_header_length",
          "insert_zone_length",
          "truncated_primary_header",
          "ocf_length",
          "applications",
        ].includes(field) && list(text)(messages),
    )
  )
    throw new Error("Invalid profile action result.");
}
