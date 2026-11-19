import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode, actor } from "@/api";
import VersionByCell from "./VersionByCell.vue";

/** #308/U25 (ca-ux after #472): a version's author in Requirements and Templates History. */
const read = (raw: unknown) => {
  const r = decode(actor, raw);
  if (!r.ok) throw new Error("bad actor");
  return r.value;
};
const cell = (raw: unknown) =>
  mount(VersionByCell, { props: { actor: raw === null ? null : read(raw) } });

describe("a version's author (U25)", () => {
  it("names a person; a nameless one is a muted 'Not known', never the id", () => {
    expect(cell({ kind: "user", id: "u-1", name: "Mira K." }).text()).toBe("Mira K.");
    const nameless = cell({ kind: "user", id: null, name: null });
    expect(nameless.text()).toBe("Not known");
    expect(nameless.get("span").classes()).toContain("text-text-3");
    expect(cell({ kind: "user", id: "u-9", name: null }).text()).not.toContain("u-9");
  });

  it("tags a service, named or not", () => {
    expect(cell({ kind: "service", id: "s-1", name: "Planner" }).text()).toBe("PlannerService");
    expect(cell({ kind: "service", id: "s-1", name: null }).text()).toBe("Not knownService");
  });

  it("says 'Not recorded' only when there's no actor at all", () => {
    expect(cell(null).text()).toBe("Not recorded");
  });
});
