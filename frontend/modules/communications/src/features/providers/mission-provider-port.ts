import { reactive, watch } from "vue";
import type { MissionPagePort } from "@cadence/plugin-sdk/mission-pages";
import { FormActionFailure } from "../../shared/form-workflow.contracts";
import { integer, record } from "../../shared/read-validation";
import { setupEnvelope, type SetupPhase } from "../../shared/mission-form-port";
import { providerReceipt } from "./useProviderOperation";
import type { ProviderPort } from "./provider-port";
export function providerPageEnvelope(value: unknown) {
  const input = record(value);
  return { ...setupEnvelope(value), sequence: integer(input.sequence) };
}
export function useMissionProviderPort(
  host: MissionPagePort,
  initial: () => { sequence: number; phase: SetupPhase; version?: number },
  resourceId?: string,
) {
  const state = reactive({ ...initial(), pending: false });
  watch(initial, (next) => {
    state.sequence = Math.max(state.sequence, next.sequence);
    state.version = Math.max(state.version ?? 0, next.version ?? 0);
    if (state.phase !== "submitted" || next.phase !== "editing") state.phase = next.phase;
  });
  function admitSequence(response: Record<string, unknown>) {
    state.sequence = Math.max(state.sequence, integer(response.sequence));
  }
  const port: ProviderPort = {
    async execute(action, input) {
      if (state.phase !== "editing") throw new FormActionFailure("unknown");
      state.phase = "submitted";
      state.pending = true;
      try {
        const sequence = state.sequence + 1;
        state.sequence = sequence;
        const response = record(
          await host.execute(action.replaceAll("_", "-"), {
            ...input,
            sequence,
            ...(resourceId ? { expected_provider_version: state.version } : {}),
          }),
        );
        // The server returns its consumed sequence even for known pre-effect rejection.
        state.sequence = integer(response.sequence);
        if (response.status === "rejected") {
          state.phase = "editing";
          throw new FormActionFailure("rejected");
        }
        if (response.status !== "ok") throw new FormActionFailure("unknown");
        const receipt = providerReceipt(response.data);
        if (resourceId && receipt.id !== resourceId) throw new FormActionFailure("unknown");
        state.version = receipt.version;
        state.phase =
          action === "create_provider" || action === "archive_provider" ? "completed" : "editing";
        return response.data;
      } finally {
        state.pending = false;
      }
    },
    async query() {
      const response = record(await host.execute("refresh", {}));
      admitSequence(response);
      if (response.status !== "ok") throw new FormActionFailure("rejected");
      const data = providerPageEnvelope(response.data);
      if (data.phase !== "editing") state.phase = data.phase;
      if (resourceId) {
        const provider = record(record(record(data.model).data).provider);
        if (
          provider.provider_id !== resourceId ||
          typeof provider.version !== "string" ||
          !/^v[1-9][0-9]*$/.test(provider.version)
        )
          throw new FormActionFailure("unknown");
        state.version = Math.max(state.version ?? 0, integer(Number(provider.version.slice(1)), 1));
      }
      return data.model;
    },
    navigate: (href) => host.navigate(href),
  };
  return { state, port };
}
