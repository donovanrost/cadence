import { describe, expect, it } from "vite-plus/test";
import type { Passes } from "@/features/contacts/index.ts";
import type { PlanDetail } from "@/features/scheduling/index.ts";
import { bookingRequests, bookingStoppedText } from "./applied.ts";

const pass = (starts_at: string, locked: boolean) => ({ starts_at, locked });
const plan = (passes: ReturnType<typeof pass>[]) =>
  ({ id: "contact_plan_new", passes }) as unknown as PlanDetail;
const read = (planIds: string[], truncated = false) =>
  ({
    from: "2026-11-10T00:00:00Z",
    to: "2026-11-10T20:00:00Z",
    truncated,
    passes: planIds.map((id) => ({ plan: { id, version: 1 } })),
  }) as unknown as Passes;

describe("bookingRequests", () => {
  it("counts moves and adds; drops send nothing", () => {
    expect(bookingRequests({ moved: [1, 2, 3, 4], added: [1] })).toBe(5);
  });
});

describe("bookingStoppedText", () => {
  const p = plan([
    pass("2026-11-10T02:30:00Z", false),
    pass("2026-11-10T07:56:00Z", false),
    pass("2026-11-10T09:00:00Z", true),
  ]);
  it("states the counts when the read covers every request", () => {
    expect(bookingStoppedText(p, read(["contact_plan_new", "contact_plan_old"]))).toBe(
      "Booking stopped. 1 request went out; 1 didn't.",
    );
  });
  it("falls back when the read is truncated or doesn't cover the plan", () => {
    const unknown = "Booking stopped before every request went out.";
    expect(bookingStoppedText(p, read([], true))).toBe(unknown);
    expect(bookingStoppedText(p, null)).toBe(unknown);
    const late = plan([pass("2026-11-10T21:00:00Z", false)]);
    expect(bookingStoppedText(late, read([]))).toBe(unknown);
  });
});
