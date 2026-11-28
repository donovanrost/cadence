import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId, scid, spacecraftId } from "@/api/index.ts";
import type { RequirementDetail } from "./requirements.ts";
import RequirementView from "./RequirementView.vue";

/** #244 (A5, B4; fe-ops on #584): after Close/Cancel, focus goes to the ended line only if it was lost. */
const requirement = (state: RequirementDetail["state"]): RequirementDetail => ({
  id: "req_1",
  state,
  version: 2,
  spacecraft: { id: spacecraftId("sc_1"), name: "EARENDIL-1", scid: scid(1) },
  template_id: null,
  template_version: null,
  content: {},
  updated_at: "2026-11-20T06:00:00Z",
  state_changed:
    state === "active"
      ? null
      : {
          at: "2026-11-20T06:00:00Z",
          by: { kind: "user", id: "u1", name: "Mira K." },
          reason: null,
        },
  rule_summary: null,
  versions: [],
  held_by: null,
  permissions: ["planning.requirement.edit"],
});

beforeEach(() => {
  vi.stubGlobal(
    "fetch",
    vi.fn(async () => new Response("{}", { status: 404 })),
  );
});
afterEach(() => vi.unstubAllGlobals());

const mountView = () =>
  mount(RequirementView, {
    props: {
      missionId: missionId("m-1"),
      requirement: requirement("active"),
      endable: true,
      canEdit: true,
    },
    attachTo: document.body,
    global: {
      stubs: {
        RequirementPlanning: true,
        // Its confirm button ends the requirement; the parent refetch then unmounts it.
        RequirementEnd: {
          emits: ["ended"],
          template: "<button data-end @click=\"$emit('ended')\">Close it</button>",
        },
      },
    },
  });

describe("focus after Close or Cancel (B4)", () => {
  it("moves to the ended line when focus was lost with the unmounted confirm", async () => {
    const w = mountView();
    try {
      const end = w.get<HTMLButtonElement>("[data-end]");
      end.element.focus();
      await end.trigger("click");
      await w.setProps({ requirement: requirement("closed"), endable: false });
      await flushPromises();
      expect(document.activeElement).toBe(w.get("[data-ended-line]").element);
    } finally {
      w.unmount();
    }
  });

  it("leaves focus where the person moved it", async () => {
    const elsewhere = document.createElement("button");
    document.body.append(elsewhere);
    const w = mountView();
    try {
      await w.get("[data-end]").trigger("click");
      elsewhere.focus();
      await w.setProps({ requirement: requirement("closed"), endable: false });
      await flushPromises();
      expect(document.activeElement).toBe(elsewhere);
    } finally {
      w.unmount();
      elsewhere.remove();
    }
  });
});
