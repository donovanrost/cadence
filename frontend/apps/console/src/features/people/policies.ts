import type { MissionId } from "@/api/index.ts";
import { decoders as d, isKnown, recordOf, request, type ApiResult, type Decoded } from "@/api";

/** O4 command policies (api commanding.md): keys + parameters; the console writes the sentences. */
export const policyKeys = [
  "command_classification",
  "policy_hint",
  "fleet_reach",
  "no_self_approval",
] as const;
export const policiesReader = d.object({
  policies: d.array(
    d.object({
      key: d.knownText(policyKeys),
      parameters: (v: unknown) => (v && typeof v === "object" ? v : {}),
    }),
    50,
  ),
});
export type CommandPolicy = Decoded<typeof policiesReader>["policies"][number];

export function fetchCommandPolicies(
  missionId: MissionId,
  signal: AbortSignal,
): Promise<ApiResult<Decoded<typeof policiesReader>>> {
  return request(`/missions/${encodeURIComponent(missionId)}/command-policies`, policiesReader, {
    signal,
  });
}

const and = (items: readonly string[]) =>
  items.length <= 1 ? (items[0] ?? "") : `${items.slice(0, -1).join(", ")} and ${items.at(-1)}`;
const or = (items: readonly string[]) =>
  items.length <= 1 ? (items[0] ?? "") : `${items.slice(0, -1).join(", ")} or ${items.at(-1)}`;
const strings = (v: unknown): string[] =>
  Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];
// ux (request_validation.ex): both hints simply require a second GO.
const hints = ["confirmation_required", "approval_required"] as const;
const hintWords: Readonly<Record<(typeof hints)[number], string>> = {
  confirmation_required: "confirmation",
  approval_required: "approval",
};
/** A catalog hint in words; one the console doesn't know reads with spaces. */
const hintText = (h: string) => {
  const known = hints.find((k) => k === h);
  return known ? hintWords[known] : h.replaceAll("_", " ");
};

/** People.md U4: each policy as a title and one sentence, from the server's effective policy. */
export function policyText(p: CommandPolicy): Readonly<{ title: string; sentence: string }> {
  const params = recordOf(p.parameters) ?? {};
  if (!isKnown(p.key))
    return {
      title: capital(p.key.unrecognized.replaceAll("_", " ")),
      sentence: "The server applies this policy; the console doesn't describe it yet.",
    };
  switch (p.key) {
    case "command_classification": {
      const classes = strings(params["classifications"]);
      return {
        title: "Two-person rule",
        sentence: `${capital(and(classes))} commands need a second GO from another person who can approve.`,
      };
    }
    case "policy_hint": {
      const marked = strings(params["hints"]).map(hintText);
      return {
        title: "Catalog markings",
        sentence: `Commands the catalog marks as needing ${or(marked)} also need a second GO.`,
      };
    }
    case "fleet_reach": {
      const n = typeof params["threshold"] === "number" ? params["threshold"] : null;
      return {
        title: "Fleet-wide reach",
        sentence:
          n === null
            ? "Requests that reach many spacecraft need a second GO."
            : `Any request to ${n} or more spacecraft needs a second GO.`, // count >= threshold (ux)
      };
    }
    case "no_self_approval":
      return {
        title: "No self-approval",
        sentence: "Nobody can give the second GO on their own request.",
      };
  }
}

const capital = (t: string) => t.charAt(0).toUpperCase() + t.slice(1);
