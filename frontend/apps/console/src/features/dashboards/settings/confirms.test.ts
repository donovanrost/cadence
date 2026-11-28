import { dashboardId as dashIdReader } from "@/api/index.ts";
import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api";
import ArchiveSection from "./ArchiveSection.vue";
import ShareCreate from "./ShareCreate.vue";
import ShareRevoke from "./ShareRevoke.vue";

/** #245: Settings' Revoke… and Archive… use the kit's in-place confirm; Create share link takes focus. */
const api = vi.hoisted(() => ({ archive: [] as unknown[], push: vi.fn(() => Promise.resolve()) }));
vi.mock("./api.ts", async (original) => ({
  ...(await original<typeof import("./api.ts")>()),
  archiveDashboard: () => Promise.resolve(api.archive.shift()),
}));
vi.mock("vue-router", async (original) => ({
  ...(await original<typeof import("vue-router")>()),
  useRouter: () => ({ push: api.push }),
}));

afterEach(() => {
  document.body.innerHTML = "";
});
const key = { missionId: missionId("m1"), dashboardId: dashIdReader("d1") };
const button = (name: string) =>
  Array.from(document.querySelectorAll("button")).find((b) => b.textContent?.trim() === name);

describe("Share link Revoke… (A1, A4, A5)", () => {
  const mountRevoke = () => {
    const fallback = document.createElement("button");
    document.body.append(fallback);
    const w = mount(ShareRevoke, {
      props: { active: true, busy: false, refusal: null, returnFocus: () => fallback },
      attachTo: document.body,
    });
    return { w, fallback };
  };

  it("opens on Cancel, never on the action, and Esc returns focus to Revoke…", async () => {
    const { w } = mountRevoke();
    const trigger = button("Revoke…");
    trigger?.focus();
    trigger?.click();
    await flushPromises();
    expect(document.activeElement).toBe(button("Cancel"));
    expect(w.emitted("revoke")).toBeUndefined();
    document.activeElement?.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Escape", bubbles: true }),
    );
    await flushPromises();
    expect(button("Revoke the link")).toBeUndefined();
    expect(document.activeElement).toBe(button("Revoke…"));
  });

  it("closes once the row is revoked, and focus goes to the caller's target", async () => {
    const { w, fallback } = mountRevoke();
    button("Revoke…")?.click();
    await flushPromises();
    button("Revoke the link")?.focus();
    button("Revoke the link")?.click();
    expect(w.emitted("revoke")).toHaveLength(1);
    await w.setProps({ active: false });
    await flushPromises();
    expect(button("Revoke the link")).toBeUndefined();
    expect(document.activeElement).toBe(fallback);
  });
});

describe("Create share link (A1, A4)", () => {
  it("focuses the chosen Data option, and Esc cancels", async () => {
    const w = mount(ShareCreate, { props: { settingsKey: key }, attachTo: document.body });
    await flushPromises();
    expect(document.activeElement?.getAttribute("role")).toBe("radio");
    expect(document.activeElement?.getAttribute("aria-checked")).toBe("true");
    document.activeElement?.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Escape", bubbles: true }),
    );
    expect(w.emitted("cancel")).toHaveLength(1);
  });
});

describe("Archive… (A1, A4, A5, D3)", () => {
  it("opens on Keep it; an in-use refusal is read under the question and the action reads Archive anyway", async () => {
    api.archive.push({
      ok: false,
      error: {
        kind: "http",
        status: 409,
        code: "dashboard_in_use",
        message: "in use",
        details: { used_by: { playlists: [{ name: "Ops wall" }] } },
      },
    });
    mount(ArchiveSection, {
      props: { settingsKey: key, archived: false },
      attachTo: document.body,
    });
    button("Archive…")?.click();
    await flushPromises();
    expect(document.activeElement).toBe(button("Keep it"));
    button("Archive the dashboard")?.click();
    await flushPromises();
    // The kit's refusal region: polite today, role="alert" once fe-ops' #486 (#463) lands.
    const regions = Array.from(document.querySelectorAll('[role="alert"], [aria-live]'));
    expect(regions.some((r) => r.textContent?.includes("Used in a playlist: Ops wall."))).toBe(
      true,
    );
    expect(button("Archive anyway")).toBeDefined();
    button("Keep it")?.click();
    await flushPromises();
    expect(document.activeElement).toBe(button("Archive…"));
  });
});
