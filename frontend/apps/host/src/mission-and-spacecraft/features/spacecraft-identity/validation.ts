import {
  assertShape,
  bool,
  choice,
  count,
  href,
  list,
  nullable,
  record,
  shape,
  text,
} from "../../shared/validation.ts";
const version = nullable((value: unknown) => count(value) && Number(value) > 0);
const field = (type: string, name: string) =>
  shape({
    id: text,
    name: choice(name),
    type: choice(type),
    label: text,
    required: bool,
    value: text,
  });
const section = shape({ id: text, number: text, title: text });
const form = shape({
  page: shape({
    id: choice("spacecraft-new-page", "spacecraft-edit-page"),
    heading: text,
    subtitle: text,
    breadcrumbs: list(shape({ label: text, href: nullable(href) })),
  }),
  form: shape({
    id: text,
    profile_version: version,
    sections: shape({ identity: section, profile: section }),
    fields: shape({
      display_name: field("text", "spacecraft[display_name]"),
      scid: field("text", "spacecraft[scid]"),
      spacecraft_type_id: field("select", "spacecraft[spacecraft_type_id]"),
    }),
    actions: shape({
      submit: shape({ id: text, label: text }),
      cancel: shape({ id: text, label: text, href }),
    }),
  }),
  profile_options: shape({
    options: list(shape({ label: text, value: text, version })),
    empty: bool,
    empty_state: shape({
      message: text,
      action: shape({ id: text, label: text, href }),
      suffix: text,
    }),
  }),
});
export function assertIdentityForm(value: unknown): void {
  assertShape(form, value);
  const data = value as import("./contracts").IdentityData;
  const selected = data.form.fields.spacecraft_type_id.value;
  const pin = data.form.profile_version;
  if (
    !data.profile_options.options.some(
      (option) => option.value === selected && option.version === pin,
    )
  )
    throw new Error("Missing selected profile binding.");
  const keys = data.profile_options.options.map((option) =>
    JSON.stringify([option.value, option.version]),
  );
  if (new Set(keys).size !== keys.length) throw new Error("Duplicate profile binding.");
  if (
    data.profile_options.options.some(
      (option) => (option.value === "") !== (option.version === null),
    )
  )
    throw new Error("Invalid profile binding.");
}
export function assertNewIdentityForm(value: unknown): void {
  assertIdentityForm(value);
  if ((value as import("./contracts").IdentityData).page.id !== "spacecraft-new-page")
    throw new Error("Wrong identity form.");
}
export function assertEditIdentityForm(value: unknown): void {
  assertIdentityForm(value);
  if ((value as import("./contracts").IdentityData).page.id !== "spacecraft-edit-page")
    throw new Error("Wrong identity form.");
}
export function assertIdentityResult(
  value: unknown,
): asserts value is { status: "ok" | "invalid"; errors: import("./contracts").IdentityErrors } {
  if (
    !record(value) ||
    !["ok", "invalid"].includes(String(value.status)) ||
    !record(value.errors) ||
    !Object.entries(value.errors).every(
      ([field, messages]) =>
        ["display_name", "scid", "spacecraft_type_id", "spacecraft_type_version"].includes(field) &&
        list(text)(messages),
    )
  )
    throw new Error("Invalid identity action result.");
}
