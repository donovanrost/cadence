import { describe, expect, it } from "vite-plus/test";

describe("fieldErrors (U79: an error sits on its field)", () => {
  const invalid = (index: number, errors: { path: string; message: string }[]) => ({
    kind: "invalid" as const,
    code: "invalid_op",
    message: "A staged change is invalid.",
    details: { index, errors },
  });
  it("puts each schema path's first message on its field and keeps the rest", async () => {
    const { fieldErrors } = await import("./fieldErrors.ts");
    const split = fieldErrors(
      invalid(0, [
        { path: "downlink", message: "Choose a role for downlink, uplink or both" },
        { path: "downlink", message: "a second one" },
        { path: "", message: "Each direction once" },
      ]),
      new Set(["downlink", "uplink"]),
    );
    expect(split).toEqual({
      onFields: { downlink: "Choose a role for downlink, uplink or both" },
      rest: [
        { path: "downlink", message: "a second one" },
        { path: "", message: "Each direction once" },
      ],
    });
  });
  it("leaves another op's errors and non-invalid_op failures alone", async () => {
    const { fieldErrors } = await import("./fieldErrors.ts");
    expect(
      fieldErrors(invalid(1, [{ path: "downlink", message: "x" }]), new Set(["downlink"])),
    ).toEqual({ onFields: {}, rest: [{ path: "downlink", message: "x" }] });
    expect(fieldErrors({ kind: "not_found", code: "x", message: "" }, new Set())).toBeNull();
  });
});
