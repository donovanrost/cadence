import { inject, provide, type InjectionKey } from "vue";
import type { ProfileSummary } from "@/features/profiles/index.ts";
import type { SpacecraftDirectory } from "../api.ts";
import type { Draft, Proposal } from "./draft.ts";

/** The wizard's draft owner (AddSpacecraftScreen) shares it with the step components. */
export type DraftContext = Readonly<{
  draft: Readonly<Draft>;
  set: <K extends keyof Draft>(key: K, value: Draft[K]) => void;
  directory: () => SpacecraftDirectory;
  profiles: () => readonly ProfileSummary[];
  proposal: () => Proposal;
}>;

const key: InjectionKey<DraftContext> = Symbol("apogee.add-spacecraft");

export function provideDraft(context: DraftContext) {
  provide(key, context);
}

export function useDraft(): DraftContext {
  const context = inject(key);
  if (!context) throw new Error("useDraft() outside the Add spacecraft flow");
  return context;
}

export const steps = ["source", "identity", "orbit", "review"] as const;
export type Step = (typeof steps)[number];
export const stepLabels: Readonly<Record<Step, string>> = {
  source: "Source",
  identity: "Identity",
  orbit: "Orbit & routing",
  review: "Review",
};
