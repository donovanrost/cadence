import { mount } from "@vue/test-utils";
import { computed } from "vue";
import { describe, expect, it, vi } from "vite-plus/test";
import { decode } from "@/api/index.ts";
import ChangesOutcome from "./ChangesOutcome.vue";
import { NOTHING_RUNNING, savedOnlyText } from "./nothingRunning.ts";
import { previewReader } from "./preview.ts";
import { submitReader } from "./submitResult.ts";

vi.mock("@/shell", async (original) => ({
  ...(await original<typeof import("@/shell")>()),
  useRuntimeStatus: () => computed(() => undefined),
}));

const applied = (o: Record<string, unknown> = {}) => {
  const r = decode(submitReader, {
    state: "applied",
    change_set_id: "cs-1",
    revision: 1,
    staged_count: 2,
    runtime: "not_applicable",
    degraded_partitions: [],
    ...o,
  });
  if (!r.ok) throw new Error(r.error.message);
  return r.value;
};
const outcome = (o: Record<string, unknown>) =>
  mount(ChangesOutcome, {
    props: { outcome: applied(o), stagedNotice: null, next: null },
    global: { stubs: { ApButton: { template: "<a><slot /></a>" } } },
  }).text();

/** ux U93: applying on a mission with nothing running says so, only on the server's word. */
describe("has_active_configuration (U93)", () => {
  it("words the before line and the after line", () => {
    expect(NOTHING_RUNNING).toBe(
      "Nothing is running on this mission yet, so applying saves these changes and starts nothing. Each spacecraft starts when its configuration is reviewed and activated.",
    );
    expect(savedOnlyText(1, 2)).toBe(
      "r1 is saved, 2 changes. Nothing is running on this mission yet, so nothing started.",
    );
  });

  it("the outcome says saved only on false; true, absent or not_applicable alone read as today", () => {
    expect(outcome({ has_active_configuration: false })).toContain(savedOnlyText(1, 2));
    for (const o of [{ has_active_configuration: true }, {}]) {
      const t = outcome(o);
      expect(t).not.toContain("Nothing is running");
      expect(t).toContain("r1 is active");
    }
  });

  it("the preview reads it as optional", () => {
    const body = { verdict: "go", checks: [], effects: [] };
    const without = decode(previewReader, body);
    const off = decode(previewReader, { ...body, has_active_configuration: false });
    expect(without.ok && without.value.has_active_configuration).toBeUndefined();
    expect(off.ok && off.value.has_active_configuration).toBe(false);
  });
});
