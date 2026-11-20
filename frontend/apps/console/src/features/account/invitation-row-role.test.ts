import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it, vi } from "vite-plus/test";
import InvitationRow from "./InvitationRow.vue";
import { decode } from "@/api";
import { myInvitationsReader, type MyInvitation } from "./invitations.ts";

/** a11y B6 (ux #276): the row says whether its act failed, so only a failure is an alert. */
const api = vi.hoisted(() => ({
  decline: { ok: true, value: null } as unknown,
}));
vi.mock("./invitations.ts", async (original) => ({
  ...(await original<typeof import("./invitations.ts")>()),
  declineInvitation: () => Promise.resolve(api.decline),
}));

const read = decode(myInvitationsReader, {
  invitations: [
    {
      id: "inv-1",
      organization: { id: "org-1", slug: "reflect-orbital", name: "Reflect Orbital" },
      role: "member",
      invited_by: null,
      invited_at: "2026-11-19T09:00:00Z",
      expires_at: null,
    },
  ],
});
if (!read.ok) throw read.error;
const invitation: MyInvitation | undefined = read.value.invitations[0];
if (!invitation) throw new Error("fixture");

async function decline() {
  const w = mount(InvitationRow, { props: { invitation } });
  const button = (text: string) => w.findAll("button").find((b) => b.text().startsWith(text));
  await button("Decline…")?.trigger("click");
  await button("Decline the invitation")?.trigger("click");
  await flushPromises();
  return w.emitted("changed")?.[0];
}

describe("InvitationRow's result (B6)", () => {
  it("a decline that went through isn't a failure", async () => {
    api.decline = { ok: true, value: null };
    expect(await decline()).toEqual(["Declined the invitation to Reflect Orbital.", false]);
  });

  it("a decline that failed is", async () => {
    api.decline = { ok: false, error: { kind: "network", message: "offline" } };
    const [text, failed] = (await decline()) ?? [];
    expect(typeof text).toBe("string");
    expect(failed).toBe(true);
  });
});
