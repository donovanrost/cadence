import { ref } from "vue";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decode, missionId, spacecraftId, type ApiError } from "@/api/index.ts";
import { snapshotReader, type ConfigurationSnapshot, type WorkspaceKey } from "./api.ts";
import { documentWire, snapshotWire } from "./fixtures.ts";
import {
  reviewLine,
  sendBlocked,
  sendLabel,
  sendOutcome,
  sendRefusal,
  sourceLine,
} from "./send-words.ts";
import { useSend } from "./useSend.ts";

/** #595c (U94): sending a spacecraft's saved configuration for activation. */
type Submit = typeof import("./api.ts").submitWorkspace;
const submit = vi.hoisted(() => ({ fn: vi.fn<Submit>() }));
vi.mock("./api.ts", async (original) => ({
  ...(await original<typeof import("./api.ts")>()),
  submitWorkspace: (...args: Parameters<Submit>) => submit.fn(...args),
}));
afterEach(() => submit.fn.mockReset());

const snap = (o: Record<string, unknown> = {}): ConfigurationSnapshot => {
  const r = decode(snapshotReader, snapshotWire(o));
  if (!r.ok) throw r.error;
  return r.value;
};
const approval = (o: Record<string, unknown>) => ({ ...snapshotWire().approval, ...o });
const idle = { dirty: false, conflict: false, sending: false };
const refused = (code: string, details: unknown = null): ApiError => ({
  kind: "conflict",
  code,
  message: "x",
  details,
});

describe("the send words", () => {
  it("names the act by the approval setting, with its source", () => {
    expect(sendLabel(snap())).toBe("Request approval for v4");
    expect(sendLabel(snap({ approval: approval({ requirement: "direct" }) }))).toBe("Activate v4");
    expect(sourceLine(snap({ approval: approval({ source: "overridden" }) }))).toBe(
      "Mission setting",
    );
    expect(sourceLine(snap())).toBe("Organization default");
    expect(sourceLine(snap({ approval: approval({ source: "enforced" }) }))).toBe(
      "Set by the organization",
    );
  });

  it("gives U94's disabled reasons in order", () => {
    const s = snap();
    expect(sendBlocked(s, { ...idle, dirty: true })).toBe("Save the draft first.");
    expect(sendBlocked(s, { ...idle, conflict: true })).toBe("Choose which version to keep first.");
    expect(sendBlocked(snap({ document: documentWire({ catalog_revision_id: null }) }), idle)).toBe(
      "Finish the steps above first.",
    );
    const active = snapshotWire().active;
    expect(sendBlocked(snap({ active: { ...active, document: documentWire() } }), idle)).toBe(
      "The draft matches the active configuration.",
    );
    expect(
      sendBlocked(
        snap({ review: { id: "r1", state: "approval_pending", requester_id: "u1", version: 4 } }),
        idle,
      ),
    ).toBe("v4 is waiting for approval.");
    expect(sendBlocked(snap({ approval: approval({ can_request: false }) }), idle)).toBe(
      "You can't activate configurations on this mission.",
    );
    expect(sendBlocked(s, idle)).toBeNull();
  });

  it("says the result, and the request's state", () => {
    const s = snap();
    expect(sendOutcome({ state: "approval_pending", request_id: "req-1" }, s)).toEqual({
      tone: "info",
      text: "Sent for approval. Another person approves v4 in Setup › Changes.",
      requestId: "req-1",
    });
    expect(sendOutcome({ state: "active" }, s).text).toBe("v4 is active on EARENDIL-004.");
    expect(sendOutcome({ state: "needs_review" }, s).text).toBe(
      "v4 is approved, but Cadence couldn't confirm it was applied yet.",
    );
    expect(
      reviewLine(snap({ review: { id: "r1", state: "stale", requester_id: "u1", version: 4 } })),
    ).toBe(
      "EARENDIL-004's configuration changed after v4 was sent, so it can't be approved. Send it again.",
    );
  });

  it("words the refusals, with Open rev 14 for one unapproved revision", () => {
    const s = snap();
    expect(
      sendRefusal(
        refused("mission_model_revision_not_approved", {
          mission_model_revision_ids: ["mm-14"],
          catalog_revision_numbers: [14],
        }),
        s,
      ),
    ).toEqual({
      text: "Not sent: catalog rev 14 isn't approved yet. An org admin approves it in Setup › Catalog first.",
      openRevision: { number: 14, revisionId: "mm-14" },
    });
    expect(
      sendRefusal(
        refused("mission_model_revision_not_approved", {
          mission_model_revision_ids: ["mm-4", "mm-5"],
          catalog_revision_numbers: [4, 5],
        }),
        s,
      ).text,
    ).toBe(
      "Not sent: catalog revs 4 and 5 aren't approved yet. An org admin approves them in Setup › Catalog first.",
    );
    expect(sendRefusal(refused("spacecraft_configuration_review_stale"), s).text).toMatch(
      /^Not sent: EARENDIL-004's active configuration changed/,
    );
    expect(sendRefusal(refused("packet_definition_version_taken"), s).text).toBe(
      "Not sent: another change saved a packet definition at the same moment. Send it again.",
    );
    // Self-approval is refused on Approve, never on a send (mms-ux): a generic line with its code.
    expect(sendRefusal(refused("activation_self_approval_forbidden"), s)).toEqual({
      text: "Not sent.",
      code: "activation_self_approval_forbidden",
    });
    expect(
      sendRefusal({ kind: "forbidden", code: "forbidden", message: "x", details: null }, s).text,
    ).toBe("Not sent: you can't activate configurations on this mission.");
    expect(sendRefusal(refused("brand_new_code"), s)).toEqual({
      text: "Not sent.",
      code: "brand_new_code",
    });
  });
});

describe("sending", () => {
  const key = ref<WorkspaceKey | null>({
    missionId: missionId("m1"),
    spacecraftId: spacecraftId("spacecraft-earendil-004"),
    section: "overview",
  });

  it("asks for review with the snapshot's tokens when the mission needs approval", async () => {
    submit.fn.mockResolvedValue({
      ok: true,
      value: { state: "approval_pending", request_id: "req-1" },
    });
    const refetch = vi.fn();
    const s = useSend(key, () => snap(), refetch);
    await s.send();
    expect(submit.fn.mock.calls[0]?.slice(1)).toEqual(["t-1", "p-1", "review"]);
    expect(s.outcome.value?.requestId).toBe("req-1");
    expect(refetch).toHaveBeenCalled();
  });

  it("says it isn't confirmed, never 'Not sent' or 'approved', when the answer can't be read", async () => {
    submit.fn.mockResolvedValue({
      ok: false,
      error: { kind: "malformed", message: "unknown state" },
    });
    const refetch = vi.fn();
    const s = useSend(key, () => snap(), refetch);
    await s.send();
    expect(s.failure.value).toBeNull();
    expect(s.outcome.value).toEqual({
      tone: "caution",
      text: "Cadence hasn't confirmed what happened to v4. Reload to see it.",
      requestId: null,
    });
    expect(refetch).toHaveBeenCalled();
  });

  it("activates directly without approval, and keeps a refusal for the panel", async () => {
    submit.fn.mockResolvedValue({ ok: false, error: refused("activation_policy_changed") });
    const s = useSend(key, () => snap({ approval: approval({ requirement: "direct" }) }), vi.fn());
    await s.send();
    expect(submit.fn.mock.calls[0]?.[3]).toBe("activate");
    expect(s.failure.value?.text).toBe(
      "Not sent: the mission's approval setting changed. Check it and send it again.",
    );
  });
});
