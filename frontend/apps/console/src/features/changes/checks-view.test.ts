import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode, type RemoteState } from "@/api";
import { previewReader, type Preview } from "./actions.ts";
import ChecksPanel from "./ChecksPanel.vue";
import { doneLine, holdsKey, type HeldChecks } from "./checks-view.ts";

/** A preview with one check per verdict given ('go' | 'hold' | 'no_go'), each hold on `entity`. */
function preview(verdicts: readonly ("go" | "hold" | "no_go")[], entity = "ld_1"): Preview {
  const keys = ["validation", "conflicts", "compatibility"] as const;
  const r = decode(previewReader, {
    verdict: verdicts.includes("no_go") ? "no_go" : verdicts.includes("hold") ? "hold" : "go",
    diffs: [],
    checks: verdicts.map((verdict, i) => ({
      key: keys[i % keys.length],
      verdict,
      items:
        verdict === "go"
          ? []
          : [{ kind: "spacecraft", entity_id: entity, reason: "spacecraft_passes_booked" }],
    })),
    effects: [],
  });
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
}

describe("K2 re-check words (ux B4)", () => {
  it("announces what the new run found", () => {
    expect(doneLine(preview(["go", "go"]))).toBe("Checks done: all GO.");
    expect(doneLine(preview(["no_go", "hold", "hold"]))).toBe("Checks done: 1 NO-GO, 2 holds.");
    expect(doneLine(preview(["hold"]))).toBe("Checks done: 1 hold.");
  });

  it("keys the holds by what they hold, so the same holds keep the acknowledgement", () => {
    expect(holdsKey(preview(["hold"]))).toBe(holdsKey(preview(["hold"])));
    expect(holdsKey(preview(["hold"]))).not.toBe(holdsKey(preview(["hold"], "ld_2")));
    expect(holdsKey(preview(["go"]))).toBe("[]");
  });
});

describe("ChecksPanel while the checks re-run (ux B4)", () => {
  const held: HeldChecks = { preview: preview(["hold"]), count: 12 };
  const panel = (state: RemoteState<Preview>, extra: Record<string, unknown> = {}) =>
    mount(ChecksPanel, {
      props: { preview: state, ...extra },
      // The hold links need the booted shell; these tests are about K2's states.
      global: {
        stubs: {
          AlarmLinks: true,
          AppInstallLinks: true,
          DependentLinks: true,
          ModelApprovalLinks: true,
        },
      },
    });

  it("reads 'Running checks…' on a first load", () => {
    expect(panel({ status: "loading" }).text()).toContain("Running checks…");
  });

  it("keeps the previous rows, dimmed and named, under 'Checking again'", () => {
    const w = panel({ status: "loading" }, { held, nowCount: 14 });
    expect(w.get('[role="status"]').text()).toBe(
      "Checking again: the change set now has 14 changes.",
    );
    expect(w.text()).toContain("From the previous check (12 changes)");
    expect(w.text()).toContain("HOLD");
    expect(w.find(".ap-mark--caution").exists()).toBe(false);
    expect(w.text()).not.toContain("Running checks…");
  });

  it("keeps them under a crit 'couldn't run' with Try again when the re-run fails", () => {
    const w = panel(
      { status: "failed", error: { kind: "unavailable", status: 0, message: "offline" } },
      { held, nowCount: 14 },
    );
    expect(w.text()).toContain("The checks couldn't run for the new changes.");
    expect(w.text()).toContain("Try again");
    expect(w.text()).toContain("From the previous check (12 changes)");
  });

  it("announces the new verdict in the same live region once results replace the rows", () => {
    const value = preview(["no_go", "hold", "hold"]);
    const w = panel({ status: "ready", value, receivedAt: new Date() }, { done: doneLine(value) });
    expect(w.get('[role="status"]').text()).toBe("Checks done: 1 NO-GO, 2 holds.");
    expect(w.text()).not.toContain("From the previous check");
  });
});
