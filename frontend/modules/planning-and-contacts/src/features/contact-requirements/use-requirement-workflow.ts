import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import {
  admitRequirementOperation,
  admitRequirementPage,
  requirementContext,
  type RequirementCommand,
  type RequirementRequest,
  type RequirementOperation,
  type RequirementPage,
} from "./requirement-workflow";
import { requirementDataEqual } from "./requirement-directory";
export function useRequirementWorkflow(
  input: () => RequirementPage,
  port: () => OpsPagePort,
  readPort: () => OpsPageReadPort,
) {
  const initial = input(),
    context = requirementContext(initial.detail),
    query = { ...initial.detail.query };
  const detail = shallowRef(initial.detail),
    operation = shallowRef(initial.operation),
    pending = ref(false),
    uncertain = ref(initial.operation?.status === "unconfirmed"),
    needsRead = ref(false),
    notice = ref("");
  let active = true,
    generation = 0,
    sequence = initial.sequence;
  let attempted: (RequirementCommand & { sequence: number }) | null = null;
  const disabled = computed(() => pending.value || uncertain.value || needsRead.value);
  const result = computed(() =>
    operation.value?.status === "completed"
      ? { actionId: operation.value.action, result: operation.value.receipt.result }
      : undefined,
  );
  const nextHref = computed(() =>
    operation.value?.status === "completed" ? operation.value.receipt.result.navigation.href : null,
  );
  function settle(op: RequirementOperation, command: NonNullable<typeof attempted>) {
    if (
      op.sequence !== command.sequence ||
      op.action !== command.action ||
      !requirementDataEqual(op.input, command.input)
    )
      throw Error("Different requirement operation");
    sequence = op.sequence;
    operation.value = op;
    uncertain.value = op.status === "unconfirmed";
    notice.value =
      op.status === "completed"
        ? "The reviewed action completed."
        : op.status === "rejected"
          ? "The action was rejected. Refresh and review current evidence before trying again."
          : "No confirmed receipt is available. Further actions are paused.";
  }
  function accept(value: unknown) {
    const next = admitRequirementPage(value, context, query);
    if (!next || next.sequence < sequence) throw Error("Unavailable requirement read");
    if (attempted && uncertain.value && next.operation?.sequence === attempted.sequence)
      settle(next.operation, attempted);
    detail.value = next.detail;
    operation.value = next.operation;
    sequence = next.sequence;
    needsRead.value = false;
  }
  async function refresh() {
    if (pending.value) return;
    const n = ++generation;
    pending.value = true;
    try {
      const next = await readPort().read();
      if (!active || n !== generation) return;
      accept(next);
      if (!uncertain.value)
        notice.value = "Requirement evidence refreshed. Valid selections are retained.";
    } catch {
      if (active && n === generation)
        notice.value = "Refresh failed. Previous evidence and selections are retained.";
    } finally {
      if (active && n === generation) pending.value = false;
    }
  }
  async function submit(...[action, payload]: RequirementRequest) {
    if (disabled.value || !active) return;
    const command: RequirementCommand & { sequence: number } =
      action === "plan"
        ? {
            action,
            input: { ...payload, requirement_evidence: { ...payload.requirement_evidence } },
            sequence: sequence + 1,
          }
        : {
            action,
            input: {
              ...payload,
              requirement_evidence: { ...payload.requirement_evidence },
              selected_snapshot_ids: [...payload.selected_snapshot_ids],
            },
            sequence: sequence + 1,
          };
    attempted = command;
    const n = ++generation;
    pending.value = true;
    notice.value = "";
    try {
      const value = await port().execute(action, {
        sequence: command.sequence,
        payload: command.input,
      });
      if (!active || n !== generation) return;
      const op = admitRequirementOperation(value, context);
      if (!op) throw Error("Unavailable requirement receipt");
      settle(op, command);
      if (op.status === "completed") {
        needsRead.value = true;
        try {
          const next = await readPort().read();
          if (!active || n !== generation) return;
          accept(next);
          notice.value = "The reviewed action completed and requirement evidence refreshed.";
        } catch {
          if (active && n === generation)
            notice.value =
              "The action completed, but evidence could not be refreshed. Refresh before another action.";
        }
      }
    } catch {
      if (active && n === generation) {
        uncertain.value = true;
        notice.value =
          "No confirmed response was received. Refresh to recover the receipt before another action.";
      }
    } finally {
      if (active && n === generation) pending.value = false;
    }
  }
  watch(input, (next) => {
    if (requirementDataEqual(next, initial)) return;
    if (pending.value) {
      generation++;
      pending.value = false;
      uncertain.value = true;
    }
    try {
      accept(next);
    } catch {
      needsRead.value = true;
      notice.value =
        "Updated requirement evidence could not be admitted. Previous evidence is retained.";
    }
  });
  onBeforeUnmount(() => {
    active = false;
    generation++;
  });
  return {
    detail,
    operation,
    pending,
    uncertain,
    disabled,
    notice,
    result,
    nextHref,
    refresh,
    submit,
  };
}
