import { flushPromises, mount, RouterLinkStub } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { defineComponent, h } from "vue";
import { decode, organizationId } from "@/api";
import type { Session, SessionOrganization } from "@/api/session.ts";
import { provideSession } from "@/shell/session.ts";
import { unreadNotices } from "@/shell/unread-notices.ts";
import NoticesPanel from "./NoticesPanel.vue";
import { noticeReader, noticeWords, organizationLink, type Notice } from "./notices.ts";

afterEach(() => vi.unstubAllGlobals());

/** Synthetic rows in the shape session.md "Account: notices" gives (#709), not from a server. */
const wire = (n: number, o: Record<string, unknown> = {}) => ({
  id: `notif_${n}`,
  kind: "organization_access_granted",
  organization: { id: `org_${n}`, name: `Org ${n}` },
  role: "member",
  created_at: "2026-11-27T10:02:00Z",
  read_at: null,
  ...o,
});
const read = (value: unknown): Notice => {
  const r = decode(noticeReader, value);
  if (!r.ok) throw new Error(JSON.stringify(r.error));
  return r.value;
};
const acme: SessionOrganization = {
  id: organizationId("org_1"),
  slug: "acme",
  name: "Acme Space",
  role: "member",
  capabilities: [],
  missions: [],
};

describe("a notice's words (#709)", () => {
  it("says who added you and as what, from a word map keyed by the role vocabulary", () => {
    const words = (n: Notice) => noticeWords(n).before + "X" + noticeWords(n).after;
    expect(words(read(wire(1)))).toBe("You were added to X as a member.");
    expect(words(read(wire(1, { role: "organization_admin" })))).toBe(
      "You were added to X as an org admin.",
    );
    // U20: a role or kind this console doesn't know says so, never a guess.
    expect(words(read(wire(1, { role: "auditor" })))).toBe("You were added to X as auditor.");
    expect(read(wire(1, { kind: "mission_granted" })).kind).toBe("unrecognized");
    expect(words(read(wire(1, { kind: "mission_granted" })))).toBe(
      "A notice this console doesn't recognize, about X.",
    );
  });

  it("links the organization only from the session's own list, when it has a mission", () => {
    const n = read(wire(1));
    expect(organizationLink(n, [])).toEqual({ name: "Org 1", to: null });
    expect(organizationLink(n, [acme])).toEqual({ name: "Acme Space", to: null });
    const withMission = {
      ...acme,
      missions: [{ id: acme.id as never, slug: "earendil", name: "Earendil" }],
    };
    expect(organizationLink(n, [withMission])).toEqual({
      name: "Acme Space",
      to: { name: "org.home", params: { org: "acme" } },
    });
    expect(organizationLink(read(wire(2, { organization: { id: "o", name: null } })), [])).toEqual({
      name: "an organization",
      to: null,
    });
  });
});

const session = (organizations: readonly SessionOrganization[]): Session => ({
  user: { id: "u", email: "ana@example.com", display_name: "Ana Reyes" },
  current_organization_id: null,
  platform_admin_eligible: false,
  capabilities: [],
  organizations: [...organizations],
  csrf_token: "t",
  socket: { path: "/socket" },
  admin_mode: false,
  admin_mode_expires_at: null,
  pending_invitations_count: null,
  unread_notices_count: 0,
});

type Answer = { status: number; body: unknown };
function server(answer: (url: URL, init?: RequestInit) => Answer) {
  const asked: { url: URL; method: string }[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn((input: string, init?: RequestInit) => {
      const url = new URL(input, "http://x");
      asked.push({ url, method: init?.method ?? "GET" });
      const a = answer(url, init);
      return Promise.resolve(new Response(JSON.stringify(a.body), { status: a.status }));
    }),
  );
  return asked;
}

async function mountPanel(organizations: readonly SessionOrganization[] = []) {
  const Host = defineComponent(() => {
    provideSession(session(organizations));
    return () => h(NoticesPanel);
  });
  const w = mount(Host, { global: { stubs: { RouterLink: RouterLinkStub } } });
  await flushPromises();
  return w;
}

describe("NoticesPanel (#709)", () => {
  it("is hidden when the first page is empty", async () => {
    server(() => ({ status: 200, body: { data: { notices: [] }, meta: { next_cursor: null } } }));
    const w = await mountPanel();
    expect(w.text()).toBe("");
  });

  it("shows a failure with Retry instead of hiding", async () => {
    server(() => ({ status: 503, body: { error: { code: "unavailable", message: "down" } } }));
    const w = await mountPanel();
    expect(w.text()).toContain("Notices");
    expect(w.findAll("button").some((b) => b.text() === "Retry")).toBe(true);
  });

  it("lists rows with Mark read on unread ones; read ones say when", async () => {
    server(() => ({
      status: 200,
      body: {
        data: { notices: [wire(1), wire(2, { read_at: "2026-11-27T11:00:00Z" })] },
        meta: { next_cursor: null },
      },
    }));
    const w = await mountPanel();
    const rows = w.findAll("li");
    expect(rows).toHaveLength(2);
    expect(rows[0]?.text()).toContain("You were added to Org 1 as a member.");
    expect(rows[0]?.findAll("button").map((b) => b.text())).toEqual(["Mark read"]);
    expect(rows[1]?.findAll("button")).toHaveLength(0);
    expect(rows[1]?.text()).toContain("Read 11-27 11:00Z");
    // Rule 9: no row-level link beyond the organization, and that only from the session.
    expect(w.findAll("a")).toHaveLength(0);
  });

  it("Mark read posts, then re-reads the list and the menu's count from the session", async () => {
    let marked = false;
    const asked = server((url, init) => {
      if (url.pathname.endsWith("/session"))
        return { status: 200, body: { data: { ...session([]), unread_notices_count: 0 } } };
      if (init?.method === "POST") {
        marked = true;
        return { status: 200, body: { data: wire(1, { read_at: "2026-11-27T12:00:00Z" }) } };
      }
      return {
        status: 200,
        body: {
          data: { notices: [wire(1, marked ? { read_at: "2026-11-27T12:00:00Z" } : {})] },
          meta: { next_cursor: null },
        },
      };
    });
    const w = await mountPanel();
    await w.get("li button").trigger("click");
    await flushPromises();
    const paths = asked.map((a) => `${a.method} ${a.url.pathname}`);
    expect(paths).toContain("POST /api/v1/account/notices/notif_1/read");
    expect(paths.filter((p) => p === "GET /api/v1/account/notices")).toHaveLength(2);
    expect(paths).toContain("GET /api/v1/session");
    expect(unreadNotices.value).toBe(0);
    expect(w.find("li button").exists()).toBe(false);
  });
});
