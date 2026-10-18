import { containing } from "../../../../../test-support/matchers";
import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import Form from "./CommsGroundStationForm.vue";
import { readForm } from "./form-validation";
import { groundStationFormPayload } from "./fixtures.test-support";
const context = { missionId: "mission-1" };
const payload = (mode: "new" | "edit" = "new") => ({
  navigation: {
    fallback_href:
      "/missions/mission-1/comms/ground-stations/" + (mode === "new" ? "new" : "station-1/edit"),
    breadcrumbs: [],
  },
  data: groundStationFormPayload(mode),
});
test.each(["new", "edit"] as const)(
  "admitted station %s form keeps native inputs and save payloads",
  async (mode) => {
    const wrapper = mount(Form, { props: readForm(payload(mode), context, mode) });
    try {
      await wrapper.get("#ground_station_display_name").setValue("Boulder");
      await wrapper.get("#ground-station-form").trigger("submit");
      expect(wrapper.emitted("save")?.[0]).toEqual([
        {
          ground_station: containing({
            display_name: "Boulder",
            ground_station_id: mode === "edit" ? "station-1" : "",
          }),
        },
      ]);
    } finally {
      wrapper.unmount();
    }
  },
);
test("station admission binds mode, edit identity, field names and mission navigation", () => {
  for (const mutate of [
    (p: ReturnType<typeof payload>) => {
      p.data.form.fields.display_name.type = "textarea";
    },
    (p: ReturnType<typeof payload>) => {
      p.data.form.fields.display_name.name = "user[admin]";
    },
    (p: ReturnType<typeof payload>) => {
      p.data.form.fields.ground_station_id.disabled = false;
    },
    (p: ReturnType<typeof payload>) => {
      p.data.form.fields.ground_station_id.value = "other";
    },
    (p: ReturnType<typeof payload>) => {
      p.data.form.actions.cancel.href = "/missions/other/comms";
    },
    (p: ReturnType<typeof payload>) => {
      p.data.mode = "new";
    },
  ]) {
    const p = payload("edit");
    mutate(p);
    expect(() => readForm(p, context, "edit")).toThrow();
  }
});
test("station unknown properties never become component props and input IDs stay unique", () => {
  const p = payload();
  expect(readForm({ ...p, data: { ...p.data, onSave: "untrusted" } }, context)).not.toHaveProperty(
    "onSave",
  );
  p.data.form.fields.provider.id = p.data.form.fields.region.id;
  expect(() => readForm(p, context)).toThrow();
});
