import type { ApTrailStep } from "@/ui";
import {
  contactOpState,
  contactStateWord,
  type ContactState,
} from "@/features/scheduling/index.ts";

/**
 * D2 state trail (Contacts.md, ScheduleFlow M1): Requested → Confirmed → In contact → Realized,
 * with off-ramps (Rejected, Unknown, Canceled, Partial, Missed). Steps up to where the contact is;
 * progress gray, outcomes marked.
 */
const PATH: Readonly<Partial<Record<ContactState, readonly ContactState[]>>> = {
  requesting: ["requesting"],
  requested: ["requested"],
  confirmed: ["requested", "confirmed"],
  in_contact: ["requested", "confirmed", "in_contact"],
  ended: ["requested", "confirmed", "in_contact", "ended"],
  realized: ["requested", "confirmed", "in_contact", "realized"],
  partial: ["requested", "confirmed", "in_contact", "partial"],
  missed: ["requested", "confirmed", "missed"],
  rejected: ["requested", "rejected"],
  unknown: ["requested", "unknown"],
  canceling: ["requested", "canceling"],
  canceled: ["requested", "canceled"],
};

export function contactTrail(state: ContactState): ApTrailStep[] {
  return (PATH[state] ?? [state]).map((s) => {
    const op = contactOpState(s);
    // In contact is progress, so gray like the rest; only outcomes carry a mark.
    if (op === "neutral" || op === "live" || op === "optional")
      return { label: contactStateWord[s] };
    return { label: contactStateWord[s], outcome: op };
  });
}
