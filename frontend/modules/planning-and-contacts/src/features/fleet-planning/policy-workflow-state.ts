import { createPolicyActionPort } from "./policy-action-port";
import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import type { GuardedOpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import {
  admitPolicyPage,
  admitPolicyCommand,
  equalPolicyData,
  policyValidation,
  type PolicyPage,
  type PolicyAction,
  type PolicyOperation,
  type PolicyCommand,
} from "./fleet-policy";
import type { PolicyEvidence } from "./policy-evidence";
type Command = PolicyCommand;
type Attempt = Pick<PolicyOperation, "sequence" | "action" | "input">;
export function usePolicyWorkflow(
  input: () => PolicyPage,
  port: () => GuardedOpsPagePort,
  readPort: () => OpsPageReadPort,
) {
  const initial = input(),
    model = shallowRef(initial.model),
    operation = shallowRef(initial.operation);
  const context = { ...initial.model.context },
    query = { ...initial.model.query };
  let sequence = initial.sequence,
    active = true,
    generation = 0;
  let queuedValidation: Command | null = null,
    queuedEffect: Command | null = null;
  let attempted: Attempt | null =
    initial.operation?.status === "unconfirmed" ? initial.operation : null;
  const pending = ref<PolicyAction | "read" | null>(null),
    queued = ref(false),
    uncertain = ref(
      initial.operation?.status === "unconfirmed" && !policyValidation(initial.operation.action),
    ),
    needsRead = ref(false),
    notice = ref("");
  const confirmedPolicyEvidence = shallowRef<PolicyEvidence | null>(null),
    confirmedGrantEvidence = shallowRef<PolicyEvidence | null>(null),
    confirmedGrantSequence = ref(0);
  const locked = computed(() => uncertain.value || needsRead.value);
  const disabled = computed(
    () =>
      locked.value ||
      queued.value ||
      pending.value === "read" ||
      (!!pending.value && !policyValidation(pending.value)),
  );
  const stopGuard = port().guardNavigation(() => {
    if (
      queued.value ||
      (pending.value && pending.value !== "read" && !policyValidation(pending.value))
    ) {
      notice.value = "Wait for the submitted action before leaving this page.";
      return false;
    }
    return true;
  });
  function settle(next: PolicyOperation, command: Attempt) {
    if (
      next.sequence !== command.sequence ||
      next.action !== command.action ||
      !equalPolicyData(next.input, command.input)
    )
      throw Error("Different policy operation");
    sequence = next.sequence;
    operation.value = next;
    uncertain.value = next.status === "unconfirmed" && !policyValidation(next.action);
    if (next.status === "completed") {
      notice.value = policyValidation(next.action)
        ? "Draft validation completed."
        : "The reviewed action completed. Refreshing policy evidence.";
      if (next.action === "save-policy") {
        const r = next.receipt.result;
        confirmedPolicyEvidence.value = {
          ...context,
          contract_version: 1,
          policy_id: r.fleetPlanningPolicyId,
          policy_version: r.fleetPlanningPolicyVersion,
          content_sha256: r.contentSha256,
        };
      }
      if (next.action === "issue-grant") {
        confirmedGrantEvidence.value = next.input.policy_evidence;
        confirmedGrantSequence.value = next.sequence;
      }
    } else
      notice.value =
        next.status === "rejected"
          ? "The action was rejected. Review the fields and current evidence before trying again."
          : "The action has no confirmed receipt. Inspect the policy and grant ledger; further changes on this page are paused.";
  }
  function acceptPage(value: unknown) {
    const next = admitPolicyPage(value, context, query);
    if (!next) throw Error("Unavailable policy read");
    if (next.sequence < sequence) throw Error("Older policy sequence");
    if (attempted) {
      const op = next.operation;
      if (op && op.sequence === attempted.sequence) settle(op, attempted);
    }
    model.value = next.model;
    sequence = next.sequence;
    operation.value = next.operation;
    needsRead.value = false;
  }
  async function readEvidence(n: number) {
    const value = await readPort().read();
    if (!active || generation !== n) return;
    acceptPage(value);
  }
  async function refresh() {
    if (pending.value) return;
    const n = ++generation;
    pending.value = "read";
    try {
      await readEvidence(n);
      if (active && generation === n && !uncertain.value)
        notice.value = "Policy and grant evidence refreshed. Unsaved inputs are retained.";
    } catch {
      if (active && generation === n)
        notice.value = "Policy refresh failed. Previous evidence and unsaved inputs are retained.";
    } finally {
      if (active && generation === n) {
        pending.value = null;
        void drain();
      }
    }
  }
  function submit(request: PolicyCommand) {
    if (!active || locked.value) return;
    const { action } = request;
    const payload: unknown = JSON.parse(JSON.stringify(request.input));
    const command = admitPolicyCommand(action, payload, context);
    if (!command) return;
    if (policyValidation(action)) {
      if (
        queuedEffect ||
        (pending.value && pending.value !== "read" && !policyValidation(pending.value))
      )
        return;
      queuedValidation = command;
    } else {
      if (
        queuedEffect ||
        (pending.value && pending.value !== "read" && !policyValidation(pending.value))
      )
        return;
      queuedEffect = command;
      queued.value = true;
      queuedValidation = null;
    }
    void drain();
  }
  async function drain() {
    if (!active || pending.value || locked.value) return;
    const command = queuedEffect ?? queuedValidation;
    if (!command) return;
    if (queuedEffect) {
      queuedEffect = null;
      queued.value = false;
    } else queuedValidation = null;
    const n = ++generation,
      current = { ...command, sequence: sequence + 1 };
    attempted = current;
    pending.value = command.action;
    notice.value = "";
    try {
      const op = await createPolicyActionPort(port(), context).execute(current);
      if (!active || generation !== n) return;
      settle(op, current);
      if (!policyValidation(command.action) && op.status === "completed") {
        needsRead.value = true;
        try {
          await readEvidence(n);
          if (active && generation === n)
            notice.value = "The reviewed action completed. Policy and grant evidence refreshed.";
        } catch {
          if (active && generation === n)
            notice.value =
              "The action completed, but current evidence could not be read. Refresh before another change.";
        }
      }
    } catch {
      if (active && generation === n) {
        // A live projection may already have delivered this exact receipt while the reply was lost.
        const known = operation.value;
        if (
          known &&
          known.status !== "unconfirmed" &&
          known.sequence === current.sequence &&
          known.action === current.action &&
          equalPolicyData(known.input, current.input)
        )
          return;
        uncertain.value = !policyValidation(command.action);
        needsRead.value = policyValidation(command.action);
        queuedEffect = null;
        queuedValidation = null;
        queued.value = false;
        notice.value = policyValidation(command.action)
          ? "Validation could not be confirmed. Refresh before validating the draft again."
          : "No confirmed response was received. Refresh to recover the page receipt before another action.";
      }
    } finally {
      if (active && generation === n) {
        pending.value = null;
        void drain();
      }
    }
  }
  watch(input, (next) => {
    if (equalPolicyData(next, initial)) return;
    if (pending.value === "read") {
      generation++;
      pending.value = null;
    }
    try {
      acceptPage(next);
      void drain();
    } catch {
      needsRead.value = true;
      notice.value =
        "The updated policy view could not be admitted. Previous evidence is retained.";
    }
  });
  onBeforeUnmount(() => {
    stopGuard();
    active = false;
    generation++;
    queuedEffect = null;
    queuedValidation = null;
  });
  return {
    model,
    operation,
    pending,
    uncertain,
    disabled,
    notice,
    submit,
    refresh,
    confirmedPolicyEvidence,
    confirmedGrantEvidence,
    confirmedGrantSequence,
  };
}
