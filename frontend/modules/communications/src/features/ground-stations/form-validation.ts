import type { GroundStationForm, Page } from "./ground-station-form.contracts.ts";
import type { ReadContext } from "../../shared/read-contracts.ts";
import { identifier, invalid, missionPath } from "../../shared/read-validation.ts";
import {
  actions,
  boolean,
  breadcrumbs,
  envelope,
  id,
  literal,
  nullable,
  object,
  section,
  string,
  unique,
} from "../../shared/form-validation.ts";

export function readForm(
  value: unknown,
  context: ReadContext,
  mode: "new" | "edit" = "new",
): { page: Page; mode: "new" | "edit"; form: GroundStationForm } {
  const field = (key: string, type: "text" | "textarea" = "text") =>
    object({
      id,
      name: literal("ground_station[" + key + "]"),
      type: literal(type),
      label: string,
      required: boolean,
      disabled: boolean,
      placeholder: nullable(string),
      value: string,
    });
  // Read identity before computing the exact edit and cancellation paths.
  const input = object({
    data: object({
      form: object({
        fields: object({
          ground_station_id: object({ value: string }),
        }),
      }),
    }),
  })(value);
  const base = missionPath(context) + "/comms/ground-stations";
  const station =
    mode === "edit" ? identifier(input.data.form.fields.ground_station_id.value) : null;
  const cancel = station === null ? base : base + "/" + encodeURIComponent(station);
  const result = object({
    page: object({ id, heading: string, subtitle: string, breadcrumbs: breadcrumbs(context) }),
    mode: literal(mode),
    form: object({
      id,
      sections: object({ identity: section, network: section, metadata: section }),
      fields: object({
        ground_station_id: field("ground_station_id"),
        display_name: field("display_name"),
        provider: field("provider"),
        region: field("region"),
        metadata_json: field("metadata_json", "textarea"),
      }),
      actions: actions(context, cancel),
    }),
  })(envelope(value, context, mode === "new" ? base + "/new" : cancel + "/edit"));
  if (result.form.fields.ground_station_id.disabled !== (mode === "edit")) invalid();
  unique(Object.values(result.form.fields).map((field) => field.id));
  return result;
}
export const readEditForm = (value: unknown, context: ReadContext) =>
  readForm(value, context, "edit");
