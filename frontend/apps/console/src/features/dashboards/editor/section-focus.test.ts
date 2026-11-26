import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { snapshotJson } from "../fixtures.test-support.ts";
import { previewReply, widgetDefaults, type Preview } from "./contracts.ts";
import EditBoard from "./EditBoard.vue";

/** A staged preview whose outline has these (empty) sections, in order. */
function preview(ids: readonly string[]): Preview {
  const r = decode(previewReply, {
    snapshot: snapshotJson(),
    changes: [],
    current_version: 3,
    outline: {
      version: 3,
      dashboard_id: "dashboard",
      document_version: 3,
      name: "Bus overview",
      description: "",
      defaults: widgetDefaults,
      runtime_defaults_json: "{}",
      grid: { columns: 12, row_height_px: 80, gap_px: 8 },
      sections: ids.map((id) => ({
        id,
        title: id.toUpperCase(),
        description: "",
        collapsed_by_default: false,
      })),
      placements: [],
    },
  });
  if (!r.ok) throw new Error("fixture");
  return r.value;
}

// The header's 'Add section' lives outside the board (EditActions); stand one in for it.
const addSection = document.createElement("button");
addSection.dataset.addSection = "";
document.body.append(addSection);
afterEach(() => {
  if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
});

/** Remove `id` through its ⋯ menu, then let the staged preview drop it, as the session would. */
async function remove(ids: string[], id: string) {
  const w = mount(EditBoard, { props: { preview: preview(ids) }, attachTo: document.body });
  const head = w.findAll("header").find((h) => h.find(`[data-section-heading="${id}"]`).exists());
  await head?.get('button[aria-label^="More actions for section"]').trigger("click");
  await head
    ?.findAll("button")
    .find((b) => b.text().startsWith("Remove section"))
    ?.trigger("click");
  expect(w.emitted("stage")?.at(-1)).toEqual([
    { event: "remove_section", input: { section_id: id } },
  ]);
  await w.setProps({ preview: preview(ids.filter((x) => x !== id)) });
  await new Promise((resolve) => setTimeout(resolve));
  const focused = document.activeElement;
  w.unmount();
  return focused;
}

describe("focus after 'Remove section' (ux a11y checklist)", () => {
  it("goes to the next section's heading", async () => {
    const focused = await remove(["a", "b", "c"], "b");
    expect(focused?.getAttribute("data-section-heading")).toBe("c");
  });
  it("goes to the previous heading when the last one goes", async () => {
    const focused = await remove(["a", "b", "c"], "c");
    expect(focused?.getAttribute("data-section-heading")).toBe("b");
  });
  it("goes to 'Add section' when the only one goes", async () => {
    expect(await remove(["a"], "a")).toBe(addSection);
  });
});
