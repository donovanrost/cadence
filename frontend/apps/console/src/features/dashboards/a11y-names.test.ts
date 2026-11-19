import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it } from "vite-plus/test";
import type { DirectoryRow } from "./directory/api.ts";
import NameCell from "./directory/NameCell.vue";
import EditSectionHead from "./editor/EditSectionHead.vue";
import JsonDiffView from "./versions/JsonDiffView.vue";

/** #245: words a screen reader reads (B2) and controls that name what they act on (B7). */
afterEach(() => {
  document.body.innerHTML = "";
});

describe("section heading controls name their section (B7)", () => {
  const head = (title: string, position = 1) =>
    mount(EditSectionHead, {
      props: {
        section: { id: "s1", title, description: "", collapsed_by_default: false },
        count: 0,
        first: true,
        last: true,
        position,
      },
    });
  const labels = (w: ReturnType<typeof head>) =>
    w.findAll("button").map((b) => b.attributes("aria-label"));

  it("names the section in Add widget here, Edit and the ⋯, keeping the visible words first", () => {
    expect(labels(head("Power"))).toEqual(
      expect.arrayContaining([
        "Add widget here, in Power",
        "Edit section Power",
        "More actions for section Power",
      ]),
    );
  });
  it("reads an untitled section by its place, so two untitled sections differ", () => {
    expect(labels(head("", 2))).toEqual(
      expect.arrayContaining([
        "Edit section Untitled section 2",
        "More actions for section Untitled section 2",
      ]),
    );
    expect(labels(head("", 3))).toContain("Edit section Untitled section 3");
  });
});

describe("Directory star (B2)", () => {
  it("reads Starred from text, with the glyph hidden", () => {
    const row = { id: "d1", name: "Power", starred: true, archived: false } as DirectoryRow;
    const w = mount(NameCell, {
      props: { row },
      global: { stubs: { RouterLink: { template: "<a><slot /></a>" } } },
    });
    expect(w.find(".sr-only").text()).toBe("Starred");
    expect(w.find('[aria-hidden="true"]').text()).toBe("★");
    expect(w.find("[aria-label]").exists()).toBe(false);
  });
});

describe("JSON diff scroll box (B7)", () => {
  it("is a named region, so its label is read", () => {
    const w = mount(JsonDiffView, { props: { before: "{}", after: '{"a":1}' } });
    expect(w.attributes("role")).toBe("region");
    expect(w.attributes("aria-label")).toBe("JSON changes");
  });
});
