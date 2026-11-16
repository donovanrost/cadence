import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { settingsReader } from "./api.ts";
import MissionSettingsField from "./MissionSettingsField.vue";

/** A governance field set for this mission (decoded, not asserted). */
function field() {
  const r = decode(settingsReader, {
    sections: [
      {
        key: "cadence.governance",
        title: "Governance",
        purpose: null,
        locked: false,
        version: null,
        fields: [
          {
            path: "approvals_required",
            label: "Approvals required",
            type: "string",
            unit: null,
            enum: null,
            range: null,
            default: null,
            required: false,
            help: null,
            visible_when: null,
            value: "2",
            source: "mission",
            inherited_value: "1",
          },
        ],
      },
    ],
    permissions: ["settings.edit"],
  });
  const f = r.ok ? r.value.sections[0]?.fields[0] : undefined;
  if (!f) throw new Error("fixture");
  return f;
}
let wrapper: ReturnType<typeof mount> | null = null;
const mountField = (confirmReset: boolean) => {
  wrapper = mount(MissionSettingsField, {
    props: {
      field: field(),
      canChange: true,
      busy: false,
      confirmReset,
      orgName: "Reflect Orbital",
    },
    attachTo: document.body,
  });
  return wrapper;
};
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
});

describe("Reset to inherited (ApInlineConfirm, design-language §7)", () => {
  it("confirms governance in place, naming the organization's value, opening on Cancel", async () => {
    const w = mountField(true);
    await w.get("button[aria-controls]").trigger("click");
    await flushPromises();
    const group = w.get('[role="group"]');
    expect(group.text()).toContain("Approvals required will follow Reflect Orbital: 1.");
    expect(group.findAll("button").map((b) => b.text())).toEqual(["Cancel", "Reset to inherited"]);
    expect(document.activeElement?.textContent?.trim()).toBe("Cancel");
    expect(w.emitted("reset")).toBeUndefined();
    await group.findAll("button")[1]?.trigger("click");
    await flushPromises();
    expect(w.emitted("reset")).toHaveLength(1);
    expect(w.find('[role="group"]').exists()).toBe(false);
  });
  it("resets other sections at once (confirmsReset decides)", async () => {
    const w = mountField(false);
    expect(w.find("button[aria-controls]").exists()).toBe(false);
    await w
      .findAll("button")
      .find((b) => b.text() === "Reset to inherited")
      ?.trigger("click");
    expect(w.emitted("reset")).toHaveLength(1);
  });
});
