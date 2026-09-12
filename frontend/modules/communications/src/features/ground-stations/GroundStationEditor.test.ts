import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import GroundStationEditor from "./GroundStationEditor.vue";
import { groundStationFormPayload } from "./fixtures.test-support";

test("a reused feature resets action state when its context and port change", async () => {
  let finishOld!: (value: unknown) => void;
  let finishNew!: (value: unknown) => void;
  const oldPort = {
    execute: vi.fn().mockReturnValue(
      new Promise((resolve) => {
        finishOld = resolve;
      }),
    ),
    navigate: vi.fn(),
  };
  const newPort = {
    execute: vi.fn().mockReturnValue(
      new Promise((resolve) => {
        finishNew = resolve;
      }),
    ),
    navigate: vi.fn(),
  };
  const wrapper = mount(GroundStationEditor, {
    props: {
      ...groundStationFormPayload("new"),
      context: { missionId: "mission-1" },
      port: oldPort,
    },
  });
  try {
    await wrapper.get("#ground_station_display_name").setValue("Old draft");
    await wrapper.setProps({ context: { missionId: "mission-2" }, port: newPort });
    await wrapper.get("#ground_station_display_name").setValue("New draft");
    expect(newPort.execute).toHaveBeenCalledTimes(1);
    finishOld({ result: { valid: true } });
    await flushPromises();
    expect(wrapper.get("#create-ground-station-button").attributes("disabled")).toBeDefined();
    finishNew({ result: { valid: true } });
    await flushPromises();
    expect(wrapper.get("#create-ground-station-button").attributes("disabled")).toBeUndefined();
    expect(oldPort.navigate).not.toHaveBeenCalled();
  } finally {
    wrapper.unmount();
  }
});

test("authoritative replacement form data invalidates prior draft approval", async () => {
  const props = groundStationFormPayload("edit");
  const port = {
    execute: vi.fn().mockResolvedValue({ result: { valid: true } }),
    navigate: vi.fn(),
  };
  const wrapper = mount(GroundStationEditor, {
    props: { ...props, context: { missionId: "mission-1" }, port },
  });
  try {
    await wrapper.get("#ground_station_display_name").setValue("Draft");
    await flushPromises();
    expect(wrapper.get("#save-ground-station-button").attributes("disabled")).toBeUndefined();
    const form = structuredClone(props.form);
    form.fields.display_name.value = "Authoritative";
    await wrapper.setProps({ form });
    expect(wrapper.get("#save-ground-station-button").attributes("disabled")).toBeDefined();
    expect((wrapper.get("#ground_station_display_name").element as HTMLInputElement).value).toBe(
      "Authoritative",
    );
  } finally {
    wrapper.unmount();
  }
});
test.each(["new", "edit"] as const)(
  "station %s saves only the validated draft and freezes native fields during save",
  async (mode) => {
    let finish!: (value: unknown) => void;
    const port = {
      execute: vi
        .fn()
        .mockResolvedValueOnce({ result: { valid: true } })
        .mockReturnValue(
          new Promise((resolve) => {
            finish = resolve;
          }),
        ),
      navigate: vi.fn(),
    };
    const wrapper = mount(GroundStationEditor, {
      props: { ...groundStationFormPayload(mode), context: { missionId: "mission-1" }, port },
    });
    try {
      await wrapper.get("#ground_station_display_name").setValue("Goldstone");
      await flushPromises();
      await wrapper.get("#ground-station-form").trigger("submit");
      expect(wrapper.get("fieldset.contents").attributes("disabled")).toBeDefined();
      expect(port.execute).toHaveBeenLastCalledWith("save", {
        ground_station: {
          ground_station_id: mode === "edit" ? "station-1" : "",
          display_name: "Goldstone",
          provider: "",
          region: "",
          metadata_json: "{}",
        },
      });
      finish({
        result: { navigation: { href: "/missions/mission-1/comms/ground-stations/station-1" } },
      });
      await flushPromises();
      expect(port.navigate).toHaveBeenCalledTimes(1);
    } finally {
      wrapper.unmount();
    }
  },
);
