import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { decoders } from "@/api";
import { accountsReader } from "./api.ts";
import RemoveAccount from "./RemoveAccount.vue";

const api = vi.hoisted(() => ({ result: { ok: true, value: null } as unknown }));
vi.mock("./api.ts", async (original) => ({
  ...(await original<typeof import("./api.ts")>()),
  removeAccount: () => Promise.resolve(api.result),
}));
vi.mock("vue-router", async (original) => ({
  ...(await original<typeof import("vue-router")>()),
  useRouter: () => ({ push: () => Promise.resolve() }),
}));

/** A decoded account (fixtures through the decoder, not assertions). */
function account() {
  const wire = {
    accounts: [
      {
        id: "pa_svalbard",
        name: "Svalbard",
        provider: { key: "ksat", label: "KSAT" },
        status: "connected",
        status_detail: null,
        expires_at: null,
        last_success_at: null,
        missions: [],
        added_at: "2026-11-10T00:00:00Z",
        added_by: null,
      },
    ],
    adapters: [],
    permissions: [],
  };
  const r = decoders.decode(accountsReader, wire);
  if (!r.ok || !r.value.accounts[0]) throw new Error("fixture");
  return r.value.accounts[0];
}
let wrapper: ReturnType<typeof mount> | null = null;
afterEach(() => {
  wrapper?.unmount();
  wrapper = null;
});

describe("Remove account (ApInlineConfirm, design-language §7)", () => {
  it("opens on Cancel, Cancel first; a refusal is read in place and the confirm stays open", async () => {
    api.result = {
      ok: false,
      error: {
        kind: "conflict",
        status: 409,
        message: "in use",
        details: { missions: [{ name: "Earendil" }] },
      },
    };
    wrapper = mount(RemoveAccount, {
      props: { orgId: "org_1", account: account() },
      attachTo: document.body,
    });
    const w = wrapper;
    await w.get("button[aria-controls]").trigger("click");
    await flushPromises();
    const group = w.get('[role="group"]');
    expect(group.findAll("button").map((b) => b.text())).toEqual(["Cancel", "Remove account"]);
    expect(document.activeElement?.textContent?.trim()).toBe("Cancel");
    await group.findAll("button")[1]?.trigger("click");
    await flushPromises();
    expect(w.get('[aria-live="polite"]').text()).toBe(
      "Used by Earendil. Unlink it from that mission first.",
    );
    expect(w.find('[role="group"]').exists()).toBe(true);
    await w.get('[role="group"]').trigger("keydown", { key: "Escape" });
    await flushPromises();
    expect(document.activeElement).toBe(w.get("button[aria-controls]").element);
  });
});
