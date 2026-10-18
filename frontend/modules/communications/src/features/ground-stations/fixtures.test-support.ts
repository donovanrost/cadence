import type { Field, Page, GroundStationForm } from "./ground-station-form.contracts";

export function groundStationFormPayload(mode: "new" | "edit"): {
  page: Page;
  mode: "new" | "edit";
  form: GroundStationForm;
} {
  const field = (key: string, type: Field["type"] = "text"): Field => ({
    id: `ground_station_${key}`,
    name: `ground_station[${key}]`,
    type,
    label: key,
    required: false,
    disabled: mode === "edit" && key === "ground_station_id",
    placeholder: null,
    value:
      key === "metadata_json"
        ? "{}"
        : mode === "edit" && key === "ground_station_id"
          ? "station-1"
          : "",
  });
  return {
    page: {
      id: "comms-ground-station-form-page",
      heading: mode === "new" ? "New Ground Station" : "Edit Ground Station",
      subtitle: "Ground station",
      breadcrumbs: [],
    },
    mode,
    form: {
      id: "ground-station-form",
      sections: {
        identity: { id: "identity", number: "01", title: "Identity" },
        network: { id: "network", number: "02", title: "Network" },
        metadata: { id: "metadata", number: "03", title: "Metadata" },
      },
      fields: {
        ground_station_id: field("ground_station_id"),
        display_name: field("display_name"),
        provider: field("provider"),
        region: field("region"),
        metadata_json: field("metadata_json", "textarea"),
      },
      actions: {
        submit: {
          id: mode === "new" ? "create-ground-station-button" : "save-ground-station-button",
          label: "Save",
        },
        cancel: {
          id: "cancel",
          label: "Cancel",
          href: "/missions/mission-1/comms/ground-stations" + (mode === "edit" ? "/station-1" : ""),
        },
      },
    },
  };
}
