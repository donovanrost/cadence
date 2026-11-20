import { mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { ref } from "vue";
import ChangesOutcome from "./ChangesOutcome.vue";
import type { SubmitResult } from "./actions.ts";

/** #276 follow-up (lead, fe-setup on #614): the outcome is said once, in the words shown. */
const said = vi.hoisted(() => ({ texts: [] as string[] }));
vi.mock("@cadence/apogee-ui", async (original) => ({
  ...(await original<typeof import("@cadence/apogee-ui")>()),
  announcePolite: (text: string) => said.texts.push(text),
}));
vi.mock("@/shell", async (original) => ({
  ...(await original<typeof import("@/shell")>()),
  useRuntimeStatus: () => ref(undefined),
}));
afterEach(() => {
  said.texts = [];
});
const stubs = { RouterLink: { template: "<a><slot /></a>" } };

describe("ChangesOutcome's announcements", () => {
  it("announces the staged line in exactly the words it shows", () => {
    const w = mount(ChangesOutcome, {
      props: { outcome: null, stagedNotice: 2, next: 7 },
      global: { stubs },
    });
    expect(said.texts).toHaveLength(1);
    expect(w.text().replace(/\s+/g, " ").trim()).toContain(said.texts[0] ?? "(nothing said)");
  });

  it("doesn't say Sent for review again when a refetch swaps in the same state", async () => {
    const inReview = () => ({ state: "in_review" }) as unknown as SubmitResult;
    const w = mount(ChangesOutcome, {
      props: { outcome: inReview(), stagedNotice: null, next: null },
      global: { stubs },
    });
    expect(said.texts).toEqual([
      "Sent for review. An org member who didn't stage any of these changes approves or sends it back.",
    ]);
    await w.setProps({ outcome: inReview() });
    expect(said.texts).toHaveLength(1);
  });
});
