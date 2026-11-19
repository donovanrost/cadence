import { effectScope, ref } from "vue";
import { missionId as missionIdReader } from "@/api/index.ts";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { useEditSession } from "./useEditSession.ts";

type Call = { signal: AbortSignal; resolve: (value: unknown) => void };
const calls = vi.hoisted((): Call[] => []);
const saves = vi.hoisted((): unknown[] => []);

// The preview request rejects with AbortError when its signal aborts, as `request` does. `save`
// answers from `saves`; editFailure stays real.
vi.mock("./api.ts", async (importOriginal) => ({
  ...(await importOriginal<typeof import("./api.ts")>()),
  save: () => Promise.resolve(saves.shift()),
  preview: (_m: string, _d: string, _draft: unknown, _r: unknown, signal: AbortSignal) =>
    new Promise((resolve, reject) => {
      calls.push({ signal, resolve });
      signal.addEventListener("abort", () =>
        reject(new DOMException("signal is aborted without reason", "AbortError")),
      );
    }),
}));

const removeSection = (n: number) =>
  ({
    event: "remove_section",
    input: { section_id: `dash_section_${String(n).padStart(32, "0")}` },
  }) as const;
const previewWith = (label: string) => ({
  ok: true,
  value: {
    current_version: 1,
    outline: { sections: [] },
    changes: [{ kind: "removed", label, detail: null }],
  },
});
const settle = () => new Promise((r) => setTimeout(r, 0));

function session() {
  const scope = effectScope();
  const dashboardId = ref("dash-1");
  const s = scope.run(() =>
    useEditSession(
      ref(missionIdReader("m-1")),
      dashboardId,
      ref({ from: "", to: "", spacecraftId: "" }),
      ref(1),
    ),
  );
  if (!s) throw new Error("scope");
  return { s, dashboardId, stop: () => scope.stop() };
}

afterEach(() => {
  calls.length = 0;
  saves.length = 0;
  localStorage.clear();
});

describe("edit session previews", () => {
  it("swallows the superseded preview's abort and lists changes only for the current draft", async () => {
    const { s, stop } = session();
    s.enter();
    s.stage(removeSection(1));
    expect(calls).toHaveLength(2);
    expect(calls[0]?.signal.aborted).toBe(true);
    await settle(); // the aborted preview's rejection must not escape (qa: unhandled AbortError)
    expect(s.changes.value).toBeNull();
    expect(s.previewing.value).toBe(true);

    calls[1]?.resolve(previewWith("Section A"));
    await settle();
    expect(s.changes.value?.map((c) => c.label)).toEqual(["Section A"]);
    expect(s.previewing.value).toBe(false);

    // A newer edit: the old list no longer describes the draft (qa: "No changes" on Save).
    s.stage(removeSection(2));
    expect(s.changes.value).toBeNull();
    calls[2]?.resolve(previewWith("Section B"));
    await settle();
    expect(s.changes.value?.map((c) => c.label)).toEqual(["Section B"]);
    stop();
  });

  it("shows the conflict from a refused save even when the re-read hasn't caught up (qa rerun)", async () => {
    const { s, stop } = session();
    s.enter();
    s.stage(removeSection(1));
    saves.push({
      ok: false,
      error: {
        kind: "conflict",
        code: "version_conflict",
        message: "Someone saved.",
        details: {
          current_version: 4,
          saved_by: { kind: "user", id: "u-2", name: "Ana P." },
          saved_at: null,
        },
      },
    });
    expect((await s.save({ message: "", defaults: { time: false, scope: false } })).ok).toBe(false);
    expect(s.conflict.value).toEqual({ currentVersion: 4, savedBy: "Ana P.", savedAt: null });
    stop();
  });

  it("drops the draft when the screen moves to another dashboard (Save as copy)", async () => {
    const { s, dashboardId, stop } = session();
    s.enter();
    s.stage(removeSection(1));
    dashboardId.value = "dash-2";
    await settle();
    expect(s.editing.value).toBe(false);
    expect(s.staged.value).toBeNull();
    stop();
  });

  it("names who saved from the channel's version event, before any save is refused (qa)", () => {
    const { s, stop } = session();
    s.enter();
    s.stage(removeSection(1));
    s.noteSaved({ currentVersion: 1, savedBy: "Me", savedAt: null }); // not newer than my base
    expect(s.conflict.value).toBeNull();
    s.noteSaved({ currentVersion: 4, savedBy: "Ana P.", savedAt: "2026-11-14T11:55:00Z" });
    expect(s.conflict.value).toEqual({
      currentVersion: 4,
      savedBy: "Ana P.",
      savedAt: "2026-11-14T11:55:00Z",
    });
    stop();
  });

  it("uses a push that arrived before editing began, once the draft is older than it", () => {
    const { s, stop } = session();
    s.noteSaved({ currentVersion: 4, savedBy: "Ana P.", savedAt: null }); // no draft yet
    s.enter(); // based on a stale read: v1
    s.stage(removeSection(1));
    expect(s.conflict.value?.savedBy).toBe("Ana P.");
    stop();
  });
});
