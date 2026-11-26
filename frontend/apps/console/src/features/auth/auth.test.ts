import { flushPromises, mount } from "@vue/test-utils";
import { createMemoryHistory, createRouter } from "vue-router";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { fetchInvitation, safeReturn, type Invitation } from "./api.ts";
import SignInScreen from "./SignInScreen.vue";
import { invitationHeader, invitationView } from "./words.ts";

const inv = (over: Partial<Invitation> = {}): Invitation => ({
  case: "new_account",
  organization: { name: "Acme Space" },
  role: "member",
  invited_by: { name: "Mira K." },
  invited_at: "2026-11-10T09:00:00Z",
  email: "ana@x.com",
  expires_at: "2026-11-17T09:00:00Z",
  withdrawn_by: undefined,
  ...over,
});

describe("auth words (ux Auth.md)", () => {
  it("heads every case with who invited whom, and words each case", () => {
    expect(invitationHeader(inv())).toBe("Mira K. invited you to Acme Space as Member on 11-10.");
    expect(invitationHeader(inv({ role: { unrecognized: "observer" } }))).toBe(
      "Mira K. invited you to Acme Space as observer on 11-10.",
    );
    expect(invitationView(inv({ case: "unrecognized" }), null).callout?.tone).toBe("off");
    // One h1 per screen (qa): terminal cases have one too.
    expect(invitationView(inv({ case: "expired" }), null).h1).toBe("Invitation expired");
    expect(invitationView(inv({ case: "signed_in_other" }), null).h1).toBe(
      "Invitation for another account",
    );
    expect(invitationHeader(inv({ invited_by: null, invited_at: null }))).toBe(
      "You're invited to Acme Space as Member.",
    );
    expect(invitationView(inv(), null).h1).toBe("Join Acme Space");
    expect(invitationView(inv({ case: "existing_account" }), null).h1).toBe(
      "Sign in to join Acme Space",
    );
    expect(invitationView(inv({ case: "signed_in_match" }), "ana@x.com").h1).toBe(
      "Join Acme Space?",
    );
    expect(invitationView(inv({ case: "signed_in_other" }), "qa@example.com").callout?.text).toBe(
      "This invitation is for ana@x.com. You're signed in as qa@example.com.",
    );
    expect(invitationView(inv({ case: "expired" }), null).callout?.text).toBe(
      "This invitation expired on 11-17. Ask Mira K. for a new one.",
    );
    expect(invitationView(inv({ case: "withdrawn" }), null).callout?.text).toBe(
      "Mira K. withdrew this invitation.",
    );
    expect(invitationView(inv({ case: "accepted" }), null).callout?.text).toBe(
      "This invitation was already accepted.",
    );
    expect(invitationView(inv({ case: "used" }), null).callout?.text).toBe(
      "This invitation was already accepted.",
    );
    expect(invitationView(inv({ case: "declined" }), null).callout?.text).toBe(
      "This invitation was declined. Ask for a new one if you want to join.",
    );
  });
  it("only honours a same-origin return_to", () => {
    expect(safeReturn("/console/acme/earendil/now")).toBe("/console/acme/earendil/now");
    expect(safeReturn("//evil.example/x")).toBeNull();
    expect(safeReturn("https://evil.example")).toBeNull();
    expect(safeReturn(undefined)).toBeNull();
  });
});

describe("invitation decoder on the live payloads (qa, api-ops e3c5d19b)", () => {
  afterEach(() => vi.unstubAllGlobals());
  const stub = (body: unknown) =>
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ data: body }), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      ),
    );
  it("reads an unknown token (every field null) and words it with no header", async () => {
    stub({
      case: "unknown",
      organization: null,
      role: null,
      invited_by: null,
      invited_at: null,
      email: null,
      expires_at: null,
    });
    const r = await fetchInvitation("x");
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(invitationHeader(r.value)).toBeNull();
    expect(invitationView(r.value, null).callout?.text).toBe("This invitation link isn't valid.");
  });
  it("reads a new_account invitation with organization {name} and no ids", async () => {
    stub({
      case: "new_account",
      organization: { name: "QA Org" },
      role: "member",
      invited_by: { name: "Qa Admin" },
      invited_at: "2026-11-13T04:00:00Z",
      email: "qa-l5-a-965955@example.com",
      expires_at: "2026-11-20T04:00:00Z",
    });
    const r = await fetchInvitation("orginvite_4njbj3gbj4_KDK6");
    expect(r.ok && [invitationView(r.value, null).h1, invitationHeader(r.value)]).toEqual([
      "Join QA Org",
      "Qa Admin invited you to QA Org as Member on 11-13.",
    ]);
  });
});

describe("SignInScreen", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });
  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

  it("never says which part was wrong; 429 counts down; a 401 on load is just anonymous", async () => {
    const assign = vi.fn();
    vi.spyOn(window.location, "assign").mockImplementation(assign);
    const fetch = vi.fn();
    fetch.mockResolvedValueOnce(json(401, { error: { code: "unauthenticated", message: "" } }));
    fetch.mockResolvedValueOnce(
      json(422, { error: { code: "credentials_incorrect", message: "No." } }),
    );
    fetch.mockResolvedValueOnce(
      json(429, {
        error: { code: "too_many_attempts", message: "", details: { retry_after: 42 } },
      }),
    );
    vi.stubGlobal("fetch", fetch);
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: "/sign-in", name: "auth.sign-in", component: { template: "<div/>" } }],
    });
    await router.push("/sign-in?return_to=/console/acme");
    const w = mount(SignInScreen, { global: { plugins: [router] } });
    await flushPromises();
    await w.get('input[type="email"]').setValue("qa@example.com");
    await w.get('input[type="password"]').setValue("wrong");
    await w.get("form").trigger("submit");
    await flushPromises();
    expect(w.text()).toContain("That email and password don't match.");
    await w.get("form").trigger("submit");
    await flushPromises();
    expect(w.text()).toContain("Too many attempts. Try again in 0:42.");
    // ux #276: the wait is said once as an alert; the ticking countdown isn't a live region.
    await flushPromises();
    expect(w.get('p[role="alert"]').text()).toBe("Too many attempts. Try again in 42 seconds.");
    const liveWithCountdown = w
      .findAll('[role="status"], [role="alert"]')
      .filter((e) => e.text().includes("0:42"));
    expect(liveWithCountdown).toHaveLength(0);
    // Blocked: the primary is disabled with the countdown as its reason (a disabled ApButton isn't a submit).
    const primary = w.findAll("button").find((b) => b.text().startsWith("Sign in"));
    expect(primary?.attributes("aria-disabled")).toBe("true");
    expect(primary?.text()).toContain("Too many attempts. Try again in 0:42.");
    w.unmount();
    expect(assign).not.toHaveBeenCalled();
  });
});
