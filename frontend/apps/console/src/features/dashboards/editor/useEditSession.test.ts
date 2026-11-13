import { effectScope, ref } from "vue";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { useEditSession } from "./useEditSession.ts";

type Call = { signal: AbortSignal; resolve: (value: unknown) => void };
const calls = vi.hoisted((): Call[] => []);

// The preview request rejects with AbortError when its signal aborts, as `request` does.
vi.mock("./api.ts", () => ({
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
  const s = scope.run(() =>
    useEditSession(ref("m-1"), ref("dash-1"), ref({ from: "", to: "", spacecraftId: "" }), ref(1)),
  );
  if (!s) throw new Error("scope");
  return { s, stop: () => scope.stop() };
}

afterEach(() => {
  calls.length = 0;
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
});
