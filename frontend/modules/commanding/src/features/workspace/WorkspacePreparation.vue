<script setup lang="ts">
import { computed, ref } from "vue";
import CadencePane from "@cadence/ui/CadencePane.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceDateTimeField from "@cadence/ui/CadenceDateTimeField.vue";
import CadenceSegmentedControl from "@cadence/ui/CadenceSegmentedControl.vue";
import CommandArguments from "../../shared/command-draft/CommandArguments.vue";
import { parseArgumentValues } from "../../shared/command-draft/exact-values";
import { opcodeLabel } from "../../shared/command-draft/opcode";
import type { ArgumentEditorDraft } from "../../shared/command-draft/argument-editor";
import type { SelectedCommand, Target } from "../../shared/command-draft/contracts";
import { priorityChoices, priorityLabel } from "../../shared/priority";
import type { Stage } from "@cadence/commanding/stage-workbench";
import type { TargetsPreview } from "./contracts";
import type { QueuePreview } from "./queue-contracts";
import type { WorkspaceDraft, TargetIntent } from "./useCommandWorkspace";
const props = defineProps<{
  command: SelectedCommand;
  targets: readonly Target[];
  spacecraftNames: Readonly<Record<string, string>>;
  draft: WorkspaceDraft;
  stage: Stage | null;
  preview: TargetsPreview | null;
  queuePreview: QueuePreview | null;
  disabled: boolean;
}>();
const emit = defineEmits<{
  close: [];
  "update:draft": [draft: WorkspaceDraft];
  remove: [target: Target];
  prepare: [intents: readonly TargetIntent[]];
  save: [];
  enqueue: [];
}>();
const shared = ref<InstanceType<typeof CommandArguments> | null>(null);
const overrides = new Map<string, InstanceType<typeof CommandArguments>>();
const feedback = ref("");
const opcode = computed(() => opcodeLabel(props.command));
const approvalCount = computed(
  () =>
    props.queuePreview?.requests.filter((request) => request.lifecycle_state === "approval_pending")
      .length ?? 0,
);
const enqueueLabel = computed(() => {
  const count = props.queuePreview?.requests.length ?? 0;
  if (approvalCount.value === count) return "Request approval";
  if (approvalCount.value > 0) return "Submit commands";
  return `Enqueue ${count === 1 ? "command" : `${count} commands`}`;
});
const valueModes = [
  { value: "shared", label: "All spacecraft" },
  { value: "individual", label: "Per spacecraft" },
];
function patch(fields: Partial<WorkspaceDraft>) {
  feedback.value = "";
  emit("update:draft", { ...props.draft, ...fields });
}
function setValueMode(valueMode: string) {
  if (props.disabled || valueMode === props.draft.valueMode) return;
  if (valueMode !== "shared" && valueMode !== "individual") return;
  patch({
    valueMode,
    arguments: shared.value?.snapshot() ?? props.draft.arguments,
  });
}
function setOverride(target: Target, draft: ArgumentEditorDraft) {
  patch({ overrides: { ...props.draft.overrides, [target.id]: draft } });
}
function targetDraft(target: Target) {
  const draft = props.draft.overrides[target.id] ?? props.draft.arguments;
  return draft ? { draft } : {};
}
function targetHeading(target: Target) {
  const spacecraft = target.spacecraft_id && props.spacecraftNames[target.spacecraft_id];
  return spacecraft ? `${spacecraft} · ${target.name || target.id}` : target.name || target.id;
}
function prepare() {
  if (props.disabled || !props.command.supported || !props.targets.length) return;
  try {
    const sharedValues = props.draft.valueMode === "shared" ? shared.value?.collect() : undefined;
    const intents = props.targets.map((target) => {
      if (props.draft.valueMode === "shared") {
        if (sharedValues === undefined) throw Error("Reopen the command before previewing.");
        return { target, arguments: sharedValues };
      }
      const editor = overrides.get(target.id);
      if (!editor) throw Error("Reopen the spacecraft values before previewing.");
      return { target, arguments: editor.collect() };
    });
    feedback.value = "";
    emit("prepare", intents);
  } catch (error) {
    feedback.value = error instanceof Error ? error.message : "Check the argument values.";
  }
}
</script>
<template>
  <CadencePane
    id="command-workspace-preparation"
    title="Preparation"
    icon="hero-adjustments-horizontal"
  >
    <template #actions>
      <CadenceSegmentedControl
        v-if="command.arguments.some((argument) => argument.fixed_value_json === null)"
        id="workspace-value-mode"
        label="Argument values"
        size="xs"
        :options="valueModes"
        :model-value="draft.valueMode"
        :disabled="disabled || !command.supported"
        @update:model-value="setValueMode"
      />
      <CadenceButton
        id="workspace-close-preparation"
        size="xs"
        variant="quiet"
        :disabled="disabled"
        aria-label="Close command preparation"
        @click="emit('close')"
        ><span class="hero-x-mark cw-icon" aria-hidden="true"
      /></CadenceButton>
    </template>
    <div class="cw-preparation">
      <div class="cw-command-identity">
        <span class="hero-command-line cw-command-icon" aria-hidden="true" />
        <div>
          <h3>{{ command.display_name || command.name }}</h3>
          <code v-if="opcode" id="workspace-command-opcode">{{ opcode }}</code>
        </div>
      </div>
      <p v-if="command.description" class="cw-description">{{ command.description }}</p>
      <p v-if="command.hazardous || command.critical" class="cw-notice">
        <span class="hero-exclamation-triangle cw-icon" aria-hidden="true" />{{
          command.hazardous ? "Hazardous command" : "Critical command"
        }}. Review each target's resolved values before creating requests.
      </p>
      <p v-if="!command.supported" class="cw-notice" role="alert">
        This command definition cannot be prepared. Choose another command or update the mission
        model.
      </p>
      <div class="cw-target-chips" aria-label="Selected endpoints">
        <button
          v-for="target in targets"
          :key="target.id"
          type="button"
          :disabled="disabled"
          :aria-label="`Remove ${target.name || target.id} from selection`"
          @click="emit('remove', target)"
        >
          {{ target.name || target.id
          }}<span class="hero-x-mark cw-small-icon" aria-hidden="true" />
        </button>
        <p v-if="!targets.length" class="cw-subtle">
          Select endpoints to prepare this command. Your edits remain here.
        </p>
      </div>
      <form id="workspace-preparation-form" @submit.prevent="prepare">
        <fieldset :disabled="disabled || !command.supported" class="cw-form-stack">
          <CommandArguments
            v-if="draft.valueMode === 'shared'"
            ref="shared"
            :arguments="command.arguments"
            v-bind="draft.arguments ? { draft: draft.arguments } : {}"
            id-prefix="workspace-shared"
            heading="Arguments"
            compact
            @update:draft="patch({ arguments: $event })"
          />
          <template v-else>
            <section
              v-for="target in targets"
              :key="target.id"
              class="cw-override"
              :aria-label="`Settings for ${target.name || target.id}`"
            >
              <CommandArguments
                :ref="
                  (instance) => {
                    if (instance)
                      overrides.set(target.id, instance as InstanceType<typeof CommandArguments>);
                    else overrides.delete(target.id);
                  }
                "
                :arguments="command.arguments"
                v-bind="targetDraft(target)"
                :id-prefix="`workspace-${target.id}`"
                :heading="targetHeading(target)"
                compact
                @update:draft="setOverride(target, $event)"
              />
            </section>
          </template>
          <details class="cw-disclosure">
            <summary>
              Priority, timing & notes
              <span class="cw-subtle">{{ priorityLabel(Number(draft.priority)) }}</span>
            </summary>
            <div class="cw-form-stack">
              <label class="cw-field"
                >Priority<select
                  id="workspace-priority"
                  :value="draft.priority"
                  class="select select-bordered w-full"
                  @change="patch({ priority: ($event.target as HTMLSelectElement).value })"
                >
                  <option
                    v-for="choice in priorityChoices()"
                    :key="choice.rank"
                    :value="String(choice.rank)"
                  >
                    {{ choice.label }}
                  </option>
                </select></label
              ><CadenceDateTimeField
                id="workspace-not-before"
                label="Not before"
                :model-value="draft.notBefore"
                :max="draft.expiresAt"
                @update:model-value="patch({ notBefore: $event })"
                @invalid="patch({})"
              /><CadenceDateTimeField
                id="workspace-expires"
                label="Expires at"
                :model-value="draft.expiresAt"
                :min="draft.notBefore"
                @update:model-value="patch({ expiresAt: $event })"
                @invalid="patch({})"
              /><label class="cw-field"
                >Draft notes<textarea
                  id="workspace-notes"
                  :value="draft.notes"
                  class="textarea textarea-bordered w-full"
                  rows="2"
                  maxlength="4000"
                  @input="patch({ notes: ($event.target as HTMLTextAreaElement).value })"
                />
              </label>
            </div>
          </details>
          <p v-if="feedback" id="workspace-argument-error" class="cw-notice" role="alert">
            {{ feedback }}
          </p>
          <CadenceButton
            id="workspace-preview-targets"
            type="submit"
            variant="primary"
            size="sm"
            :disabled="disabled || !targets.length || !command.supported"
            >Preview {{ targets.length }} endpoint{{
              targets.length === 1 ? "" : "s"
            }}</CadenceButton
          >
        </fieldset>
      </form>
      <section
        v-if="queuePreview"
        id="workspace-target-preview"
        class="cw-resolved"
        aria-label="Resolved endpoint previews"
      >
        <h3>{{ queuePreview.requests.length }} endpoints validated</h3>
        <article
          v-for="request in queuePreview.requests"
          :key="request.request_id"
          class="cw-preview-item"
        >
          <h4>{{ request.target.name || request.target.id }}</h4>
          <code class="cw-subtle">{{ request.target.id }}</code>
          <dl>
            <div
              v-for="(value, name) in parseArgumentValues(
                request.resolved_argument_values_json,
                131072,
              )"
              :key="name"
            >
              <dt>{{ name }}</dt>
              <dd>{{ value }}</dd>
            </div>
          </dl>
          <p class="cw-subtle">
            {{ priorityLabel(request.priority) }} ·
            {{ request.not_before || "No start restriction" }} ·
            {{ request.expires_at || "No expiry" }}
          </p>
          <p v-if="request.lifecycle_state === 'approval_pending'" class="cw-notice">
            Requires approval before queueing.
          </p>
        </article>
        <CadenceButton
          id="workspace-enqueue"
          variant="primary"
          size="sm"
          :disabled="disabled"
          @click="emit('enqueue')"
          ><span class="hero-queue-list cw-small-icon" aria-hidden="true" />{{
            enqueueLabel
          }}</CadenceButton
        >
        <p v-if="preview?.notes" class="cw-description">{{ preview.notes }}</p>
        <CadenceButton
          v-if="preview && stage?.can_edit_items"
          id="workspace-save-targets"
          variant="outline"
          size="sm"
          :disabled="disabled"
          @click="emit('save')"
          >Add {{ preview.items.length }} drafts to {{ stage?.name }}</CadenceButton
        >
      </section>
      <slot name="result" />
    </div>
    <template #footer
      ><span>Queued commands run when timing and uplink conditions allow.</span></template
    >
  </CadencePane>
</template>
