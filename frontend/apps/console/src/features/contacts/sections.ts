import type { ApTabLink } from "@/ui";

/** The Contacts section tabs, one list for every Contacts screen (A12 History adds itself here). */
export const contactsSections: readonly ApTabLink[] = [
  { key: "live", label: "Live", to: { name: "ops.contacts" } },
  { key: "plan", label: "Plan", to: { name: "ops.contacts.plan" } },
  { key: "review", label: "Review", to: { name: "ops.contacts.review" } },
  { key: "history", label: "History", to: { name: "ops.contacts.history" } },
];
