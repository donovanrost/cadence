import { decoders as d, request, type ApiResult, type Decoded } from "@/api";

/** O4 command policies (api commanding.md): keys + parameters; the console writes the sentences. */
export const policiesReader = d.object({
  policies: d.array(
    d.object({ key: d.token, parameters: (v: unknown) => (v && typeof v === "object" ? v : {}) }),
    50,
  ),
});
export type CommandPolicy = Decoded<typeof policiesReader>["policies"][number];

export function fetchCommandPolicies(
  missionId: string,
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
const hintWords: Readonly<Record<string, string>> = {
  confirmation_required: "needing confirmation",
  approval_required: "needing approval",
};

/** People.md U4: each policy as a title and one sentence, from the server's effective policy. */
export function policyText(p: CommandPolicy): Readonly<{ title: string; sentence: string }> {
  const params = p.parameters as Record<string, unknown>;
  switch (p.key) {
    case "command_classification": {
      const classes = strings(params["classifications"]);
      return {
        title: "Two-person rule",
        sentence: `${capital(and(classes))} commands need a second GO from another person who can approve.`,
      };
    }
    case "policy_hint": {
      const hints = strings(params["hints"]).map((h) => hintWords[h] ?? h.replaceAll("_", " "));
      return {
        title: "Catalog markings",
        sentence: `Commands the catalog marks as ${or(hints)} are held for it.`,
      };
    }
    case "fleet_reach": {
      const n = typeof params["threshold"] === "number" ? params["threshold"] : null;
      return {
        title: "Fleet-wide reach",
        sentence:
          n === null
            ? "Requests that reach many spacecraft need a second GO."
            : `Any request to more than ${n} spacecraft needs a second GO.`,
      };
    }
    case "no_self_approval":
      return {
        title: "No self-approval",
        sentence: "Nobody can give the second GO on their own request.",
      };
    default:
      return {
        title: capital(p.key.replaceAll("_", " ")),
        sentence: "The server applies this policy; the console doesn't describe it yet.",
      };
  }
}

const capital = (t: string) => t.charAt(0).toUpperCase() + t.slice(1);
