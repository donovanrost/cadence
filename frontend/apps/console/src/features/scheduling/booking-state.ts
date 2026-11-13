import type { GanttBarKind } from "@/ui";
import { stationCode, type PlanPass } from "./api.ts";

/**
 * K1 executing: each drafted bar shows its own booking (api 8e), Requested → Confirmed /
 * Rejected (ScheduleFlow K1 `executing`). Words go with every look (never colour alone).
 */
export type BookingLook = Readonly<{ kind: GanttBarKind; word: string }>;

const LOOKS: Readonly<Record<string, BookingLook>> = {
  never_sent: { kind: "scheduled", word: "Requested" },
  confirmed: { kind: "own", word: "Confirmed" },
  uncertain: { kind: "unconfirmed", word: "Unconfirmed" },
  rejected: { kind: "clash", word: "Rejected" },
  failed: { kind: "problem", word: "Failed" },
};

/** Null before execution, and for a state this console doesn't know (drawn as drafted). */
export function bookingLook(booking: PlanPass["booking"]): BookingLook | null {
  if (!booking) return null;
  const look = LOOKS[booking.state];
  if (!look) return null;
  return booking.state === "never_sent" && booking.reason === "sending"
    ? { ...look, word: "Requested · sending" }
    : look;
}

/** `rejected_capacity` → "rejected capacity": server codes in words until ux names them. */
const words = (code: string) => code.replaceAll("_", " ");

/** Rejections become Demand rows (ScheduleFlow K1): which pass, and why when the server says. */
export function rejectedRows(passes: readonly PlanPass[]) {
  return passes.flatMap((p) => {
    const b = p.booking;
    if (!b || (b.state !== "rejected" && b.state !== "failed")) return [];
    const when = `${stationCode(p.station)} ${p.starts_at.slice(11, 16)}Z`;
    const verb = b.state === "rejected" ? "Rejected" : "Failed";
    return [
      {
        snapshotId: p.snapshot_id,
        spacecraftId: p.spacecraft_id,
        sentence: `${verb} · ${when}${b.reason ? `: ${words(b.reason)}` : ""}`,
      },
    ];
  });
}
