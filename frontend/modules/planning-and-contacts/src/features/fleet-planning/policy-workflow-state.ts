import { createPolicyActionPort } from "./policy-action-port";
import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
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
export function usePolicyWorkflow(
  input: () => PolicyPage,
  port: () => OpsPagePort,
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
  let attempted: (Command & { sequence: number }) | null = null;
  const pending = ref<PolicyAction | "read" | null>(null),
    queued = ref(false),
    uncertain = ref(initial.operation?.status === "unconfirmed"),
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
  function settle(next: PolicyOperation, command: Command & { sequence: number }) {
    if (
      next.sequence !== command.sequence ||
      next.action !== command.action ||
      !equalPolicyData(next.input, command.input)
    )
      throw Error("Different policy operation");
    sequence = next.sequence;
    operation.value = next;
    uncertain.value = next.status === "unconfirmed";
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
    if (attempted && uncertain.value) {
      const op = next.operation;
      if (op && op.sequence === attempted.sequence) settle(op, attempted);
    }
    if (next.sequence < sequence) throw Error("Older policy sequence");
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
        uncertain.value = true;
        queuedEffect = null;
        queuedValidation = null;
        queued.value = false;
        notice.value =
          "No confirmed response was received. Refresh to recover the page receipt before another action.";
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
    if (pending.value) {
      uncertain.value = true;
      generation++;
      pending.value = null;
    }
    try {
      acceptPage(next);
    } catch {
      needsRead.value = true;
      notice.value =
        "The updated policy view could not be admitted. Previous evidence is retained.";
    }
  });
  onBeforeUnmount(() => {
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
