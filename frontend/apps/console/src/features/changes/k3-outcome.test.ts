import { mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import ApplyTiles from "./ApplyTiles.vue";
import {
  authorsLine,
  outcomeReader,
  readinessAfterLine,
  routesDelta,
  type Outcome,
} from "./outcome.ts";

/** #522 (ca-engineer's shape; ca-ux's K3 words) and K9's Authors line. */
const read = (raw: unknown): Outcome => {
  const r = decode(outcomeReader, raw);
  if (!r.ok || !r.value) throw new Error("unread");
  return r.value;
};
const OUTCOME = {
  spacecraft: { now: 499, after: 549 },
  routes: { now: 1200, after: 1500, added: 300, removed: 0 },
  readiness: {
    now: { blocker: 0, caution: 2, stale: 0, not_set_up: 1 },
    after: { blocker: 0, caution: 2, stale: 0, not_set_up: 0 },
  },
};

describe("K3's outcome words", () => {
  it("reads every part as optional, and null as not computed", () => {
    expect(decode(outcomeReader, null)).toEqual({ ok: true, value: null });
    expect(decode(outcomeReader, undefined)).toEqual({ ok: true, value: undefined });
    expect(read({ spacecraft: { now: 1, after: 2 } }).routes).toBeUndefined();
  });

  it("words the Routes delta: net, or both when both", () => {
    const r = (added: number, removed: number) => routesDelta({ now: 0, after: 0, added, removed });
    expect(r(300, 0)).toBe("+300");
    expect(r(0, 50)).toBe("−50");
    expect(r(0, 0)).toBe("0");
    expect(r(300, 50)).toBe("+300 −50");
    expect(r(1200, 0)).toBe("+1,200");
  });

  it("words readiness after: blockers always, the rest only when nonzero now or after", () => {
    const o = read(OUTCOME);
    if (!o.readiness) throw new Error("no readiness");
    expect(readinessAfterLine(o.readiness)).toBe(
      "Readiness after: 0 blockers (no change) · 2 cautions (no change) · 0 not set up (was 1)",
    );
  });
});

describe("K9's Authors line", () => {
  const person = (id: string, name: string | null) => ({ kind: "user", id, name });
  const service = (id: string, name: string) => ({ kind: "service", id, name });
  it("reads the viewer as 'you', first; a service with its mark; three names, then 'and N more'", () => {
    expect(
      authorsLine(
        [
          person("u2", "Mira K."),
          person("u1", "Ana"),
          service("s1", "Ops bot"),
          person("u3", "Bo"),
        ],
        "u1",
      ),
    ).toBe("Staged by you, Mira K., Ops bot (a service identity) and 1 more");
    expect(authorsLine([person("u2", "Mira K."), service("s1", "Ops bot")], null)).toBe(
      "Staged by Mira K. and Ops bot (a service identity)",
    );
  });

  it("drops a nameless person from the names but keeps the count true", () => {
    expect(authorsLine([person("u2", "Mira K."), person("u4", null)], null)).toBe(
      "Staged by Mira K. and 1 more",
    );
    expect(authorsLine([person("u4", null), person("u5", null)], null)).toBe("Staged by 2 people");
    expect(authorsLine([person("u4", null)], null)).toBe("Staged by 1 person");
    // The system actor is Cadence, never "1 person" (U103, mms-ux on #578).
    expect(authorsLine([{ kind: "system", id: null, name: null }], null)).toBe("Staged by Cadence");
    // A nameless service is named as one, never counted among people (ca-ux on #578).
    expect(authorsLine([person("u4", null), { kind: "service", id: "s9", name: null }], null)).toBe(
      "Staged by a service identity and 1 more",
    );
    expect(authorsLine([], null)).toBe("");
  });
});

describe("ApplyTiles", () => {
  it("shows Changes · Spacecraft · Routes and the readiness line with an outcome", () => {
    const w = mount(ApplyTiles, {
      props: { staged: 3, outcome: read(OUTCOME), authors: [], viewerId: null },
    });
    expect(w.text()).toContain("Changes");
    expect(w.text()).toContain("Spacecraft");
    expect(w.text()).not.toContain("SC");
    expect(w.text()).toContain("549");
    expect(w.text()).toContain("+300");
    expect(w.find("[data-readiness-after]").exists()).toBe(true);
  });

  it("shows the Changes tile alone when the server sends no outcome (before #522)", () => {
    const w = mount(ApplyTiles, {
      props: { staged: 3, outcome: undefined, authors: [], viewerId: null },
    });
    expect(w.text()).not.toContain("Spacecraft");
    expect(w.text()).not.toContain("Routes");
    expect(w.find("[data-not-worked-out]").exists()).toBe(false);
  });

  it("keeps the tiles as dashes and says why when the outcome is null (ux 11-20)", () => {
    const w = mount(ApplyTiles, {
      props: { staged: 3, outcome: null, authors: [], viewerId: null },
    });
    expect(w.text()).toContain("Spacecraft");
    expect(w.text()).toContain("Routes");
    expect(w.text()).toContain("—");
    expect(w.get("[data-not-worked-out]").text()).toBe(
      "Cadence couldn't work out these changes' effect on the fleet and its readiness. The checks still run.",
    );
    expect(w.find("[data-readiness-after]").exists()).toBe(false);
  });

  it("says nothing about readiness when only readiness is null (the set touches nothing it reads)", () => {
    const w = mount(ApplyTiles, {
      props: {
        staged: 3,
        outcome: read({ ...OUTCOME, readiness: null }),
        authors: [],
        viewerId: null,
      },
    });
    expect(w.find("[data-readiness-after]").exists()).toBe(false);
    expect(w.find("[data-not-worked-out]").exists()).toBe(false);
  });
});
