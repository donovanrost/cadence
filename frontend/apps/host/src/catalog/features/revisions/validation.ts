import {
  assertShape,
  bool,
  breadcrumbs,
  detailCard,
  shape,
  text,
} from "../../shared/validation.ts";
export function assertRevision(value: unknown): void {
  assertShape(
    shape({
      revision: shape({ title: text, number_label: text }),
      navigation: breadcrumbs,
      provenance: detailCard,
      runtime_usage: shape({
        id: text,
        title: text,
        summary_id: text,
        summary: text,
        action: shape({ id: text, label: text, disabled: bool }),
      }),
      mission_model: (value) =>
        detailCard(value) && shape({ available: bool, empty_message: text })(value),
    }),
    value,
  );
}
