import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId as missionIdReader } from "@/api";
import { kindSchemaReader } from "./kindSchema.ts";
import KindEditor from "./KindEditor.vue";

const fixture = decode(kindSchemaReader, {
  kind: "ground_station",
  fields: [
    {
      path: "code",
      label: "Code",
      type: "string",
      unit: null,
      enum: null,
      range: null,
      default: null,
      required: false,
      help: null,
      visible_when: null,
    },
  ],
});
vi.mock("./kindSchema.ts", async (original) => ({
  ...(await original<typeof import("./kindSchema.ts")>()),
  fetchKindSchema: () => Promise.resolve(fixture),
}));
vi.mock("vue-router", async (original) => ({
  ...(await original<typeof import("vue-router")>()),
  useRouter: () => ({ push: () => Promise.resolve() }),
}));

let wrapper: ReturnType<typeof mount> | null = null;
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
});

describe("KindEditor suggestion (ux U25: 'Suggested: INU' + 'Use INU')", () => {
  it("offers the value until the field holds it, and only fills the form", async () => {
    wrapper = mount(KindEditor, {
      props: {
        missionId: missionIdReader("m1"),
        kind: "ground_station",
        entityId: "gs_inu",
        document: { code: null },
        name: "Inuvik",
        index: "G2",
        surface: "stations",
        done: { name: "setup.stations" },
        suggestion: { path: "code", value: "INU" },
      },
      global: { stubs: { RouterLink: { template: "<a><slot /></a>" } } },
    });
    await flushPromises();
    expect(wrapper.text()).toContain("Suggested: INU");
    const use = wrapper.findAll("button").find((b) => b.text() === "Use INU");
    await use?.trigger("click");
    await flushPromises();
    expect(wrapper.find<HTMLInputElement>("input").element.value).toBe("INU");
    expect(wrapper.text()).not.toContain("Suggested: INU");
  });
});
