import { describe, expect, it } from "vite-plus/test";
import { decode, type ApiError } from "@/api";
import { failureText, outcomeText, resolveReader } from "./api.ts";

const reply = (body: unknown) => {
  const r = decode(resolveReader, body);
  if (!r.ok) throw r.error;
  return r.value;
};
const resolution = {
  actor: { kind: "user", id: "u1", name: "Mira K." },
  at: "2026-11-10T10:52:00Z",
  note: "Called the ops desk.",
  provider_reference: "NL-48213",
};

describe("outcomeText (U32)", () => {
  it("says the provider settled it and nothing was marked", () => {
    const booked = reply({
      outcome: "provider_answered",
      provider_answer: "booked",
      resolution: null,
    });
    const not = reply({
      outcome: "provider_answered",
      provider_answer: "not_booked",
      resolution: null,
    });
    expect(outcomeText(booked, "Northlight")).toBe(
      "Northlight answered: booked. Nothing was marked.",
    );
    expect(outcomeText(not, "Northlight")).toBe(
      "Northlight answered: not booked. Nothing was marked.",
    );
  });
  it("names the reference on an attestation and never claims the cancel was accepted", () => {
    const attested = reply({ outcome: "attested", provider_answer: null, resolution });
    const notBooked = reply({ outcome: "not_booked", provider_answer: null, resolution });
    expect(outcomeText(attested, "Northlight")).toBe("Marked booked by you · ref NL-48213.");
    expect(outcomeText(notBooked, "Northlight")).toBe(
      "Marked not booked. The cancel went to Northlight.",
    );
  });
});

describe("failureText (U32 / U20)", () => {
  const conflict = (code: string, details: unknown): ApiError => ({
    kind: "conflict",
    code,
    message: code,
    details,
  });
  it("names who resolved it when the reply carries the actor, and refreshes", () => {
    expect(
      failureText(conflict("booking_already_resolved", { actor: resolution.actor }), "N"),
    ).toEqual({
      text: "Mira K. already resolved this.",
      fields: {},
      refresh: true,
    });
    expect(failureText(conflict("booking_already_resolved", { actor: null }), "N").text).toBe(
      "Someone already resolved this.",
    );
  });
  it("says the provider may have answered when it's no longer unconfirmed", () => {
    const f = failureText(conflict("booking_not_unconfirmed", null), "Northlight");
    expect(f.text).toBe("This booking isn't unconfirmed any more. Northlight may have answered.");
    expect(f.refresh).toBe(true);
  });
  it("puts invalid fields inline and doesn't claim anything on a dropped connection", () => {
    const invalid: ApiError = {
      kind: "invalid",
      code: "invalid_params",
      message: "invalid",
      details: { note: ["can't be blank"] },
    };
    expect(failureText(invalid, "N")).toEqual({
      text: null,
      fields: { note: "can't be blank" },
      refresh: false,
    });
    const dropped = failureText({ kind: "unavailable", status: 0, message: "" }, "N");
    expect(dropped.text).toContain("may or may not have been recorded");
    expect(dropped.refresh).toBe(true);
    expect(failureText({ kind: "forbidden", code: "forbidden", message: "no" }, "N").text).toBe(
      "Org admins resolve unconfirmed bookings.",
    );
  });
});
