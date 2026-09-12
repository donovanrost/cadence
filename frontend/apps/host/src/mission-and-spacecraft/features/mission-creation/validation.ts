import {
  assertShape,
  bool,
  choice,
  href,
  list,
  nullable,
  shape,
  text,
} from "../../shared/validation.ts";
import type MissionNew from "./MissionNew.vue";
const field = shape({
  id: text,
  name: text,
  type: choice("text"),
  label: text,
  required: bool,
  value: text,
});
const creation = shape({
  page: shape({
    id: text,
    heading: text,
    breadcrumbs: list(shape({ label: text, href: nullable(href) })),
  }),
  form: shape({
    id: text,
    fields: shape({ display_name: field, slug: field }),
    actions: shape({
      submit: shape({ id: text, label: text }),
      cancel: shape({ id: text, label: text, href }),
    }),
  }),
});
export function assertCreation(
  value: unknown,
): asserts value is Pick<InstanceType<typeof MissionNew>["$props"], "page" | "form"> {
  assertShape(creation, value);
}
