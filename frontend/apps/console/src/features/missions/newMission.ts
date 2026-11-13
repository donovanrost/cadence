import { decoders as d, detailsOf, fieldErrors, orNull, type ApiError } from "@/api";
import { failureOutcome } from "@/features/changes/index.ts";
import type { MissionSlugCheck } from "./api.ts";

/** "earendil is taken; earendil-2 is free." (null while free or unchecked). */
export function takenLine(check: MissionSlugCheck | null): string | null {
  if (!check || check.available) return null;
  return `${check.slug} is taken${check.suggestion ? `; ${check.suggestion} is free` : ""}.`;
}

/** Why Create mission is off, or null when it can go. */
export function blockedReason(
  input: Readonly<{ name: string; slug: string; taken: string | null; busy: boolean }>,
): string | null {
  if (!input.name.trim()) return "Name the mission first.";
  if (!input.slug) return "Give it a slug.";
  if (input.taken) return "Choose another slug.";
  return input.busy ? "Creating…" : null;
}

export type CreateFailure = Readonly<{
  name: string | null;
  slug: string | null;
  text: string | null;
}>;

/** M2's 422 lands on the fields (a slug clash with the free suggestion); the rest is one sentence. */
export function createFailure(error: ApiError): CreateFailure {
  if (error.kind === "forbidden")
    return { name: null, slug: null, text: "Only organization admins can create missions." };
  const fields = fieldErrors(error);
  const name = fields["name"] ?? null;
  const slugError = fields["slug"] ?? null;
  if (name || slugError) {
    const hint = detailsOf(error, d.object({ suggestion: orNull(d.string) }))?.suggestion;
    return {
      name,
      slug: slugError && hint ? `${slugError} ${hint} is free.` : slugError,
      text: null,
    };
  }
  return { name: null, slug: null, text: failureOutcome(error, "changed").sentence };
}
