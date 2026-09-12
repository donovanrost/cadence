import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import {
  admitDeclarationValues,
  admitDeclarationOperation,
  admitDeclarationPage,
  declarationDefaults,
  declarationFeedbackText,
  type DeclarationAction,
  type DeclarationOperation,
  type DeclarationPage,
  type SpacecraftChoices,
} from "./declaration";
import type { ContactRequirementPayload } from "./OpsContactRequirementNew.contracts";
import { requirementDataEqual as equal } from "./requirement-directory";
type Command = { action: DeclarationAction; input: Record<string, any> };
export function useDeclarationWorkflow(
  input: () => DeclarationPage,
  port: () => OpsPagePort,
  readPort: () => OpsPageReadPort,
) {
  const initial = input(),
    model = shallowRef(initial.model),
    operation = shallowRef(initial.operation);
  const context = { ...initial.model.context },
    horizon = { ...initial.model.horizon };
  const draft = ref(declarationDefaults(initial.model));
  const selected = shallowRef<SpacecraftChoices["entries"][number] | undefined>(
    initial.model.spacecraft.entries[0],
  );
  let sequence = initial.sequence,
    active = true,
    generation = 0;
  let validation: Command | null = null,
    choice: Command | null = null,
    save: Command | null = null;
  let attempted: (Command & { sequence: number }) | null = null;
  const pending = ref<DeclarationAction | "read" | null>(null),
    queuedSave = ref(false),
    uncertain = ref(initial.operation?.status === "unconfirmed"),
    notice = ref("");
  const created = computed(
    () => operation.value?.action === "save" && operation.value.status === "completed",
  );
  const disabled = computed(
    () =>
      uncertain.value ||
      created.value ||
      queuedSave.value ||
      pending.value === "save" ||
      !model.value.can_declare,
  );
  const inputNotice = ref("");
  const feedback = computed(() => {
    if (inputNotice.value) return inputNotice.value;
    const op = operation.value;
    if (!op || !equal(op.input.contact_requirement, draft.value)) return "";
    return declarationFeedbackText(
      op.status === "rejected"
        ? (op.feedback ?? [])
        : op.action === "validate" && op.status === "completed"
          ? op.receipt!.result.feedback
          : [],
    );
  });
  function settle(op: DeclarationOperation, command: Command & { sequence: number }) {
    if (
      op.sequence !== command.sequence ||
      op.action !== command.action ||
      !equal(op.input, command.input)
    )
      throw Error("Different declaration operation");
    sequence = op.sequence;
    operation.value = op;
    uncertain.value = op.status === "unconfirmed";
    if (op.status === "completed") {
      if (op.action === "spacecraft-page")
        model.value = {
          ...model.value,
          spacecraft: op.receipt!.result.spacecraft,
          can_declare: op.receipt!.result.spacecraft.total > 0,
        };
      notice.value =
        op.action === "save"
          ? "Contact need declared. Open the requirement to review it and start planning."
          : op.action === "spacecraft-page"
            ? "Spacecraft choices updated. Your declaration is retained."
            : op.receipt!.result.valid
              ? "Declaration validated."
              : "Review the declaration feedback.";
    } else
      notice.value =
        op.status === "rejected"
          ? "The request was rejected. Review the fields before trying again."
          : "No confirmed receipt is available. Refresh before another action.";
  }
  function acceptPage(value: unknown) {
    const next = admitDeclarationPage(value, context, horizon);
    if (!next || next.sequence < sequence) throw Error("Unavailable declaration read");
    if (next.sequence === sequence && !equal(next.operation, operation.value))
      throw Error("Changed declaration receipt");
    if (next.sequence > sequence) {
      if (!attempted || !next.operation) throw Error("Unexpected declaration sequence");
      settle(next.operation, attempted);
    }
    model.value = next.model;
  }
  async function refresh() {
    if (pending.value) return;
    const n = ++generation;
    pending.value = "read";
    try {
      const next = await readPort().read();
      if (!active || generation !== n) return;
      acceptPage(next);
      if (!uncertain.value && !created.value)
        notice.value = "Declaration context refreshed. Your draft is retained.";
    } catch {
      if (active && generation === n)
        notice.value = "Refresh failed. Your draft and any confirmed receipt are retained.";
    } finally {
      if (active && generation === n) {
        pending.value = null;
        void drain();
      }
    }
  }
  function submit(action: DeclarationAction, payload: Record<string, any>) {
    if (!active || uncertain.value || created.value || queuedSave.value || pending.value === "save")
      return;
    const command = { action, input: JSON.parse(JSON.stringify(payload)) };
    if (action === "save") {
      save = command;
      queuedSave.value = true;
      validation = null;
      choice = null;
    } else if (action === "validate") validation = command;
    else choice = command;
    void drain();
  }
  function update(action: "validate" | "save", payload: ContactRequirementPayload) {
    if (disabled.value) return;
    draft.value = { ...payload.contact_requirement };
    selected.value =
      model.value.spacecraft.entries.find((c) => c.id === draft.value.spacecraft_id) ??
      (selected.value?.id === draft.value.spacecraft_id ? selected.value : undefined);
    if (!admitDeclarationValues(draft.value)) {
      inputNotice.value = "Shorten the declaration fields before validating or saving.";
      validation = null;
      return;
    }
    inputNotice.value = "";
    submit(action, payload);
  }
  async function drain() {
    if (!active || pending.value || uncertain.value || created.value) return;
    const command = save ?? choice ?? validation;
    if (!command) return;
    if (save) {
      save = null;
      queuedSave.value = false;
    } else if (choice) choice = null;
    else validation = null;
    const n = ++generation,
      current = { ...command, sequence: sequence + 1 };
    attempted = current;
    pending.value = command.action;
    try {
      const result = await port().execute(command.action, {
        sequence: current.sequence,
        payload: command.input,
      });
      if (!active || generation !== n) return;
      const op = admitDeclarationOperation(result, context);
      if (!op) throw Error("Unavailable receipt");
      settle(op, current);
    } catch {
      if (active && generation === n) {
        uncertain.value = true;
        save = null;
        choice = null;
        validation = null;
        queuedSave.value = false;
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
    if (equal(next, initial)) return;
    if (pending.value) {
      uncertain.value = true;
      generation++;
      pending.value = null;
    }
    try {
      acceptPage(next);
    } catch {
      uncertain.value = true;
      notice.value =
        "The updated declaration context could not be admitted. Your draft is retained.";
    }
  });
  const releaseGuard = port().guardNavigation?.(
    () => pending.value !== "save" && !queuedSave.value,
  );
  onBeforeUnmount(() => {
    active = false;
    generation++;
    validation = null;
    choice = null;
    save = null;
    releaseGuard?.();
  });
  return {
    model,
    operation,
    draft,
    selected,
    pending,
    uncertain,
    created,
    disabled,
    notice,
    feedback,
    update,
    submit,
    refresh,
  };
}
