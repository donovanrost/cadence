import { describe, expect, it } from "vite-plus/test";
import {
  ingestionNote,
  ingestionOptions,
  ingestionReadBack,
  ingestionSaveLabel,
  isOffered,
} from "./ingestion.ts";

const p = "Northlight";

describe("booking updates (ux U77, api-ops' ingestion mode)", () => {
  it("offers only Cadence checks and Off, in that order", () => {
    expect(ingestionOptions(p)).toEqual([
      { value: "polling", label: "Cadence checks" },
      { value: "disabled", label: "Off" },
    ]);
    expect(isOffered("webhook")).toBe(false);
  });

  it("words Off on Add, and what an Edit changes", () => {
    expect(ingestionNote("disabled", null, p)?.text).toBe(
      "While this is off, Cadence won't see Northlight confirm, move or cancel bookings. Turn it on in Edit when the account is ready.",
    );
    expect(ingestionNote("disabled", "polling", p)?.text).toBe(
      "While this is off, Cadence won't see Northlight confirm, move or cancel the bookings made with this account.",
    );
    expect(ingestionNote("polling", "disabled", p)).toEqual({
      tone: "info",
      text: "Cadence starts taking in Northlight's changes when you save.",
    });
    expect(ingestionNote("polling", "polling", p)).toBeNull();
    expect(ingestionNote("polling", null, p)).toBeNull();
    expect(ingestionSaveLabel("disabled", "polling")).toBe("Save and turn off updates");
    expect(ingestionSaveLabel("disabled", "disabled")).toBe("Save");
    expect(ingestionSaveLabel("polling", "disabled")).toBe("Save");
  });

  it("reads back the mode, Off with its consequence, and a seeded webhook account", () => {
    expect(ingestionReadBack("disabled", p)).toEqual({
      value: "Off",
      off: "Cadence won't see Northlight's booking changes.",
    });
    expect(ingestionReadBack("webhook", p)).toEqual({ value: "Northlight sends", off: null });
    expect(ingestionReadBack(undefined, p)).toBeNull();
    expect(ingestionReadBack({ unrecognized: "batched_push" }, p)).toEqual({
      value: "batched push",
      off: null,
    });
  });
});
