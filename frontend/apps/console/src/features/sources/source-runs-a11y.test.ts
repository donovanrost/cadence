import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { missionId } from "@/api/index.ts";
import SourceRuns from "./SourceRuns.vue";
import type { SourceRun } from "./writes.ts";

/** #244 (A6/B7): the Retry/Requeue explanation is visible once, and each button points at it. */
const run = (
  job_id: string,
  actions: SourceRun["actions"],
  status: SourceRun["status"],
): SourceRun => ({
  job_id,
  kind: "reconcile",
  status,
  started_at: "2026-11-20T04:00:00Z",
  error: null,
  actions,
});

describe("SourceRuns actions", () => {
  it("says what Retry does under the table, and the button points at that line", () => {
    const w = mount(SourceRuns, {
      props: {
        missionId: missionId("m-1"),
        editable: true,
        runs: [run("j1", ["retry"], "failed")],
      },
    });
    const line = w.findAll("p").find((p) => p.text() === "Retry starts a failed run again.");
    expect(line).toBeTruthy();
    const button = w.findAll("button").find((b) => b.text() === "Retry");
    expect(button?.attributes("aria-describedby")).toBe(line?.attributes("id"));
    expect(w.text()).not.toContain("Requeue puts");
  });

  it("says nothing when no run offers an action, or the viewer can't act", () => {
    const none = mount(SourceRuns, {
      props: {
        missionId: missionId("m-1"),
        editable: true,
        runs: [run("j1", undefined, "completed")],
      },
    });
    expect(none.text()).not.toContain("Retry starts");
    const viewer = mount(SourceRuns, {
      props: {
        missionId: missionId("m-1"),
        editable: false,
        runs: [run("j1", ["retry"], "failed")],
      },
    });
    expect(viewer.text()).not.toContain("Retry starts");
  });
});
