import { containing } from "../../../../../test-support/matchers";
import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CommsGroundStationForm from "./CommsGroundStationForm.vue";
import { groundStationFormPayload } from "./fixtures.test-support";

test("station identity, metadata and draft events remain feature-owned", async () => {
  const props = groundStationFormPayload("new");
  const wrapper = mount(CommsGroundStationForm, { props });
  try {
    await wrapper.get("#ground_station_display_name").setValue("Boulder");
    await wrapper.get("#ground_station_metadata_json").setValue('{"antenna":"A"}');
    const input = {
      ground_station: {
        ground_station_id: "",
        display_name: "Boulder",
        provider: "",
        region: "",
        metadata_json: '{"antenna":"A"}',
      },
    };
    expect(wrapper.emitted("validate")?.at(-1)).toEqual([input]);
    await wrapper.get("#ground-station-form").trigger("submit");
    expect(wrapper.emitted("save")).toEqual([[input]]);
    expect(wrapper.get("a#cancel").attributes("href")).toBe(
      "/missions/mission-1/comms/ground-stations",
    );
  } finally {
    wrapper.unmount();
  }
});

test("editing retains the immutable station identifier and accepts authoritative form updates", async () => {
  const props = groundStationFormPayload("edit");
  props.form.fields.ground_station_id.value = "station-1";
  const wrapper = mount(CommsGroundStationForm, { props });
  try {
    expect(wrapper.get("#ground_station_ground_station_id").attributes("disabled")).toBeDefined();
    const form = structuredClone(props.form);
    form.fields.display_name.value = "Updated station";
    await wrapper.setProps({ form });
    expect((wrapper.get("#ground_station_display_name").element as HTMLInputElement).value).toBe(
      "Updated station",
    );
    await wrapper.get("#ground-station-form").trigger("submit");
    expect(wrapper.emitted("save")?.[0]).toEqual([
      {
        ground_station: containing({
          ground_station_id: "station-1",
          display_name: "Updated station",
        }),
      },
    ]);
  } finally {
    wrapper.unmount();
  }
});
