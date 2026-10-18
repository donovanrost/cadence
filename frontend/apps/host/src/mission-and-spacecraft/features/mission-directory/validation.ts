import {
  assertShape,
  attrs,
  bool,
  choice,
  count,
  href,
  list,
  shape,
  text,
} from "../../shared/validation.ts";
const label = shape({ class: text, text });
const action = shape({ attrs, class: text, icon_class: text, label: text });
const row = shape({
  id: text,
  display_name: text,
  slug: text,
  spacecraft_count: count,
  status: choice("info", "ready", "attention"),
  status_label: text,
  href,
});
const directory = shape({
  presentation: shape({
    root_class: text,
    header: shape({
      class: text,
      content_class: text,
      eyebrow: label,
      title: shape({ class: text, text, suffix: label }),
      actions_class: text,
      action,
    }),
    empty_state: shape({
      visible: bool,
      id: text,
      class: text,
      icon_class: text,
      title: label,
      description: label,
      action_container_class: text,
      action,
    }),
    card: shape({ visible: bool, class: text, body_class: text, rows: list(row) }),
  }),
});
export function assertDirectory(value: unknown): void {
  assertShape(directory, value);
}
