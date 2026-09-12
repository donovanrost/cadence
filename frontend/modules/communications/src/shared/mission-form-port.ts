import type { MissionPagePort } from "@cadence/plugin-sdk/mission-pages";
import { FormActionFailure, type FormPort } from "./form-workflow.contracts";
import { record, choice } from "./read-validation";
export type SetupPhase = "editing" | "submitted" | "completed";
export function setupEnvelope(value: unknown) {
  const input = record(value);
  return {
    model: input.model,
    phase: choice(input.phase, ["editing", "submitted", "completed"]) as SetupPhase,
  };
}
export function missionFormPort(transport: MissionPagePort): FormPort {
  return {
    async execute(action, input) {
      const response = await transport.execute(action, input);
      const envelope = record(response);
      if (envelope.status === "rejected") throw new FormActionFailure("rejected");
      if (envelope.status !== "ok" || !("data" in envelope)) throw new FormActionFailure("unknown");
      return envelope.data;
    },
    navigate: (href) => transport.navigate(href),
  };
}
