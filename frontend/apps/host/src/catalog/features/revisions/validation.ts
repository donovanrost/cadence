import {
  assertShape,
  bool,
  breadcrumbs,
  detailCard,
  shape,
  text,
} from "../../shared/validation.ts";
import { readSpacecraftUsage } from "./spacecraft-usage.ts";
export function assertRevision(value: unknown): void {
  assertShape(
    shape({
      revision: shape({ title: text, number_label: text }),
      navigation: breadcrumbs,
      provenance: detailCard,
      spacecraft_usage: (value) => {
        readSpacecraftUsage(value);
        return true;
      },
      mission_model: (value) =>
        detailCard(value) && shape({ available: bool, empty_message: text })(value),
    }),
    value,
  );
}
