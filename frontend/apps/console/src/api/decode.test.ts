import { describe, expect, it, vi } from "vite-plus/test";
import {
  array,
  DecodeError,
  decode,
  isKnown,
  known,
  knownText,
  vocabularyText,
  nullable,
  object,
  oneOf,
  optional,
  string,
  token,
  variant,
  literal,
} from "./decode.ts";
import { sessionReader } from "./session.ts";

describe("readers", () => {
  it("reports the JSON path of the first violation", () => {
    const read = object({ items: array(object({ id: token })) });
    const result = decode(read, { items: [{ id: "a" }, { id: " b" }] });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.path).toBe("items[1].id");
  });

  it("distinguishes null from absence", () => {
    expect(nullable(string)(null)).toBeNull();
    expect(() => nullable(string)(undefined)).toThrow(DecodeError);
    expect(optional(string)(undefined)).toBeUndefined();
    expect(() => optional(string)(null)).toThrow(DecodeError);
  });

  it("enforces array bounds and closed sets", () => {
    expect(() => array(string, 1)(["a", "b"])).toThrow(DecodeError);
    expect(() => oneOf(["a", "b"])("c")).toThrow(DecodeError);
  });

  it("reads a growing vocabulary as its union, with new values as 'unrecognized'", () => {
    const state = known(["active", "closed"]);
    expect(state("closed")).toBe("closed");
    expect(state("archived")).toBe("unrecognized");
    expect(() => state(3)).toThrow(DecodeError);
  });

  it("knownText keeps a new value's raw text and can't widen back to string", () => {
    const state = knownText(["active", "closed"]);
    expect(state("archived")).toEqual({ unrecognized: "archived" });
    const words = { active: "Active", closed: "Closed" } as const;
    expect(vocabularyText(state("closed"), words)).toBe("Closed");
    expect(vocabularyText(state("archived"), words)).toBe("archived");
    const value = state("closed");
    expect(isKnown(value) ? value : null).toBe("closed");
    // A misspelled literal is a compile error, not a silent false (the point of the object form).
    // @ts-expect-error TS2367: no overlap between the vocabulary and "clossed"
    expect(value === "clossed").toBe(false);
  });

  it("reports each unrecognized value once per field, and keeps the type closed", () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const state = known(["active", "closed"]);
    const read: "active" | "closed" | "unrecognized" = state("archived", "plans[0].state");
    expect(read).toBe("unrecognized");
    state("archived", "plans[0].state");
    state("paused", "plans[0].state");
    expect(warn).toHaveBeenCalledTimes(2);
    warn.mockRestore();
  });

  it("dispatches discriminated unions on the tag", () => {
    const read = variant("status", {
      done: object({ status: literal("done"), at: string }),
      pending: object({ status: literal("pending") }),
    });
    expect(read({ status: "done", at: "x" })).toEqual({ status: "done", at: "x" });
    expect(() => read({ status: "other" })).toThrow(DecodeError);
  });
});

describe("session contract", () => {
  const valid = {
    user: { id: "user_1", email: "a@example.com", display_name: null },
    current_organization_id: "org_1",
    admin_mode: false,
    platform_admin_eligible: false,
    capabilities: ["organization_operate"],
    organizations: [
      {
        id: "org_1",
        slug: "reflect-orbital",
        name: "Reflect Orbital",
        role: "member",
        capabilities: [],
        missions: [{ id: "mission_1", slug: "earendil", name: "Earendil" }],
      },
    ],
    csrf_token: "token",
    socket: { path: "/socket" },
  };

  it("accepts the documented shape", () => {
    expect(decode(sessionReader, valid).ok).toBe(true);
  });

  it("rejects a mission without a slug", () => {
    const broken = {
      ...valid,
      organizations: [{ ...valid.organizations[0], missions: [{ id: "m", name: "x" }] }],
    };
    const result = decode(sessionReader, broken);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.path).toBe("organizations[0].missions[0].slug");
  });
});
