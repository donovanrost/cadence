import { computed, onBeforeUnmount, ref, shallowRef, watch } from "vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import {
  admitTemplateValues,
  admitTemplateOperation,
  admitTemplatePage,
  templateDefaults,
  templateFeedbackText,
  templatePure,
  isTemplateCompletion,
  type TemplateCompletion,
  type TemplateCommand,
  type TemplateRequest,
  type TemplateLifecycleAction,
  type TemplatePage,
  type TemplateOperation,
  type TemplateAction,
} from "./templates";
import { requirementDataEqual as equal } from "./requirement-directory";
import type { TemplateValues } from "./OpsContactRequirementTemplate.contracts";
import type { SpacecraftChoices } from "./declaration";
type Command = TemplateCommand;
export function useTemplateWorkflow(
  input: () => TemplatePage,
  port: () => OpsPagePort,
  readPort: () => OpsPageReadPort,
) {
  const initial = input(),
    model = shallowRef(initial.model),
    operation = shallowRef(initial.operation),
    draft = ref(templateDefaults(initial.model)),
    selected = shallowRef<SpacecraftChoices["entries"][number]>();
  const context = { ...initial.model.context },
    defaults = { ...initial.model.defaults };
  let sequence = initial.sequence,
    active = true,
    generation = 0;
  let validation: Command | null = null,
    effect: Command | null = null,
    attempted: (Command & { sequence: number }) | null = null;
  const pending = ref<TemplateAction | "read" | null>(null),
    queued = ref(false),
    uncertain = ref(initial.operation?.status === "unconfirmed"),
    needsRead = ref(false),
    notice = ref(""),
    confirmed = shallowRef<TemplateCompletion | null>(
      initial.operation && isTemplateCompletion(initial.operation) ? initial.operation : null,
    );
  const locked = computed(() => uncertain.value || needsRead.value),
    disabled = computed(
      () =>
        locked.value || queued.value || (!!pending.value && pending.value !== "validate-template"),
    );
  const inputNotice = ref("");
  const feedback = computed(() => {
    if (inputNotice.value) return inputNotice.value;
    const op = operation.value;
    if (
      !op ||
      (op.action !== "validate-template" && op.action !== "create-template") ||
      !equal(op.input.template, draft.value)
    )
      return "";
    return templateFeedbackText(
      op.status === "rejected"
        ? (op.feedback ?? [])
        : op.action === "validate-template" && op.status === "completed"
          ? op.receipt.result.feedback
          : [],
    );
  });
  function settle(op: TemplateOperation, command: Command & { sequence: number }) {
    if (
      op.sequence !== command.sequence ||
      op.action !== command.action ||
      !equal(op.input, command.input)
    )
      throw Error("Different template receipt");
    sequence = op.sequence;
    operation.value = op;
    uncertain.value = op.status === "unconfirmed";
    if (op.status === "completed") {
      if (isTemplateCompletion(op)) {
        confirmed.value = op;
        notice.value = "The reviewed template action completed.";
        if (op.action === "create-template" && equal(draft.value, op.input.template)) {
          draft.value = templateDefaults(model.value);
          selected.value = undefined;
        }
      } else
        notice.value =
          op.action === "validate-template"
            ? op.receipt.result.valid
              ? "Template validated."
              : "Review the template feedback."
            : "Template page updated. Your draft is retained.";
    } else {
      notice.value =
        op.status === "rejected"
          ? templateFeedbackText(op.feedback ?? [])
          : "No confirmed receipt is available. Refresh before another action.";
      if (op.status === "rejected" && op.feedback.includes("stale_evidence"))
        needsRead.value = true;
    }
  }
  function acceptPage(value: unknown) {
    const next = admitTemplatePage(value, context, defaults);
    if (!next || next.sequence < sequence) throw Error("Unavailable template ledger");
    if (next.sequence === sequence && !equal(next.operation, operation.value))
      throw Error("Changed receipt");
    if (next.sequence > sequence) {
      if (!attempted || !next.operation) throw Error("Unexpected template sequence");
      settle(next.operation, attempted);
    }
    model.value = next.model;
    needsRead.value = false;
  }
  async function read(n: number) {
    const value = await readPort().read();
    if (active && generation === n) acceptPage(value);
  }
  async function refresh() {
    if (pending.value) return;
    const n = ++generation;
    pending.value = "read";
    try {
      await read(n);
      if (active && generation === n && !uncertain.value)
        notice.value = "Template ledger refreshed. Unsaved inputs are retained.";
    } catch {
      if (active && generation === n)
        notice.value =
          "Refresh failed. Previous evidence, draft and confirmed receipt are retained.";
    } finally {
      if (active && generation === n) {
        pending.value = null;
        void drain();
      }
    }
  }
  function submit(...[action, payload]: TemplateRequest) {
    if (
      !active ||
      locked.value ||
      queued.value ||
      (pending.value && pending.value !== "validate-template")
    )
      return;
    if (!action.endsWith("-page") && !model.value.can_manage) return;
    const command: TemplateCommand =
      action === "templates-page" || action === "spacecraft-page"
        ? { action, input: { page: payload.page } }
        : action === "validate-template" || action === "create-template"
          ? { action, input: { template: { ...payload.template } } }
          : { action, input: { reference: { ...payload.reference } } };
    if (action === "validate-template") validation = command;
    else {
      effect = command;
      queued.value = true;
      validation = null;
    }
    void drain();
  }
  function update(
    action: "validate-template" | "create-template",
    payload: { template: TemplateValues },
  ) {
    if (disabled.value || !model.value.can_manage) return;
    draft.value = { ...payload.template };
    selected.value =
      model.value.spacecraft.entries.find((c) => c.id === draft.value.spacecraft_id) ??
      (selected.value?.id === draft.value.spacecraft_id ? selected.value : undefined);
    if (!admitTemplateValues(draft.value)) {
      inputNotice.value = "Shorten the template fields before validating or saving.";
      validation = null;
      return;
    }
    inputNotice.value = "";
    if (action === "create-template") submit("create-template", payload);
    else submit("validate-template", payload);
  }
  function lifecycle(action: TemplateLifecycleAction, payload: { id: string }) {
    const row = model.value.templates.entries.find((e) => e.reference.template_id === payload.id);
    if (!row) return;
    const state = row.reference.lifecycle_state;
    if (
      (action === "pause-template" && state !== "active") ||
      (action === "activate-template" && state !== "paused") ||
      (action === "close-template" && state === "closed")
    )
      return;
    switch (action) {
      case "pause-template":
        submit(action, { reference: row.reference });
        break;
      case "activate-template":
        submit(action, { reference: row.reference });
        break;
      case "close-template":
        submit(action, { reference: row.reference });
        break;
    }
  }
  async function drain() {
    if (!active || pending.value || locked.value) return;
    const command = effect ?? validation;
    if (!command) return;
    if (effect) {
      effect = null;
      queued.value = false;
    } else validation = null;
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
      const op = admitTemplateOperation(result, context);
      if (!op) throw Error("Unavailable receipt");
      settle(op, current);
      if (op.status === "completed" && op.action !== "validate-template") {
        needsRead.value = true;
        try {
          await read(n);
        } catch {
          if (active && generation === n)
            notice.value =
              "The action completed, but the ledger could not be refreshed. Refresh before another change.";
        }
      }
    } catch {
      if (active && generation === n) {
        uncertain.value = true;
        effect = null;
        validation = null;
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
    if (equal(next, initial)) return;
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
        "Updated template evidence could not be admitted. Previous evidence and draft are retained.";
    }
  });
  const release = port().guardNavigation?.(
    () =>
      !queued.value && (!pending.value || pending.value === "read" || templatePure(pending.value)),
  );
  onBeforeUnmount(() => {
    active = false;
    generation++;
    validation = null;
    effect = null;
    release?.();
  });
  return {
    model,
    operation,
    draft,
    selected,
    pending,
    uncertain,
    disabled,
    notice,
    feedback,
    confirmed,
    submit,
    update,
    lifecycle,
    refresh,
  };
}
