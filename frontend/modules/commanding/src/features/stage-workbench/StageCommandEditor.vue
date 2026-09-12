<script setup lang="ts">
import { parseArgumentValues } from "../../shared/command-draft/exact-values";
import { priorityChoices, priorityLabel } from "../../shared/priority";
import { computed, reactive, ref } from "vue";
import CommandArguments from "../../shared/command-draft/CommandArguments.vue";
import { previewInput, type Catalog, type Query } from "../../shared/command-draft/contracts";
import { order as validOrder, text } from "../../shared/stages/validation";
import type { Item, ItemPreview } from "./contracts";
const props = defineProps<{
  catalog: Catalog;
  item: Item | null;
  stageToken: string;
  disabled: boolean;
  preview: ItemPreview | null;
  href: (changes: Partial<Query>) => string;
  follow: (event: MouseEvent, href: string) => void;
}>();
const emit = defineEmits<{
  preview: [input: Record<string, unknown>];
  save: [notes: string, order: number];
  edited: [];
  navigate: [href: string];
}>();
const controls = ref<InstanceType<typeof CommandArguments> | null>(null),
  feedback = ref("");
const form = reactive({
  priority: String(props.item?.priority ?? 3),
  notBefore: props.item?.not_before ?? "",
  expiresAt: props.item?.expires_at ?? "",
  notes: props.item?.notes ?? "",
  order: String(props.item?.order ?? 0),
});
const searches = reactive({
  target_query: props.catalog.query.target_query,
  command_query: props.catalog.query.command_query,
});
const ready = computed(
  () => props.catalog.selected_command?.supported && !!props.catalog.selected_target,
);
const supplied = computed(() =>
  props.item?.command_id === props.catalog.selected_command?.id
    ? (props.item?.argument_values_json ?? undefined)
    : undefined,
);
function search(kind: "target" | "command") {
  if (!props.disabled)
    emit(
      "navigate",
      props.href(
        kind === "target"
          ? { target_query: searches.target_query, target_after: "" }
          : { command_query: searches.command_query, command_after: "" },
      ),
    );
}
function edited() {
  feedback.value = "";
  emit("edited");
}
function resolvePreview() {
  if (props.disabled || !ready.value) return;
  try {
    const command = previewInput(
      props.catalog,
      controls.value?.collect() ?? "{}",
      form.priority,
      form.notBefore,
      form.expiresAt,
    );
    emit("preview", {
      expected_stage: props.stageToken,
      expected_item: props.item?.expected_item ?? null,
      command,
    });
  } catch (error) {
    feedback.value =
      error instanceof Error && !error.message.startsWith("Unavailable")
        ? error.message
        : "Check the arguments, priority and UTC timing before previewing.";
  }
}
function save() {
  if (props.disabled || !props.preview) return;
  if (
    !text(form.notes, 4000) ||
    !/^(0|[1-9]\d*)$/.test(form.order) ||
    !validOrder(Number(form.order))
  ) {
    feedback.value = "Use notes up to 4,000 UTF-8 bytes and an order between 0 and 2147483647.";
    return;
  }
  emit("save", form.notes, Number(form.order));
}
</script>
<template>
  <section id="stage-command-editor" class="space-y-4" aria-labelledby="stage-command-editor-title">
    <h2 id="stage-command-editor-title" class="font-semibold">
      {{ item ? "Change draft command" : "Add a command draft" }}
    </h2>
    <p class="text-xs text-base-content/60">
      Active model <span class="font-mono break-all">{{ catalog.basis.revision_id }}</span> ·
      Generation {{ catalog.basis.generation }}
    </p>
    <p v-if="feedback" role="alert" class="text-sm text-warning">{{ feedback }}</p>
    <div v-if="!ready" class="grid gap-4 lg:grid-cols-2">
      <section class="border border-base-300 bg-base-100 p-4 space-y-3" aria-label="Choose target">
        <h3 class="text-sm font-semibold">Target endpoint</h3>
        <form id="stage-target-search" class="flex gap-2" @submit.prevent="search('target')">
          <input
            id="stage-target-query"
            v-model="searches.target_query"
            aria-label="Search target endpoints"
            class="input input-bordered input-sm min-w-0 flex-1"
            maxlength="240"
          /><button class="btn btn-ghost btn-sm" :disabled="disabled">Search</button>
        </form>
        <p v-if="catalog.selected_target" class="text-xs text-info">
          Selected: {{ catalog.selected_target.name || catalog.selected_target.id }}
        </p>
        <p v-else-if="catalog.query.target" class="text-xs text-warning">
          The selected target is unavailable. Choose a current endpoint.
        </p>
        <ul id="stage-targets" class="divide-y divide-base-300">
          <li v-for="target in catalog.targets.entries" :key="target.id">
            <a
              :href="href({ target: target.id })"
              class="block py-3 text-sm hover:text-info"
              @click="follow($event, href({ target: target.id }))"
              >{{ target.name || target.id
              }}<span class="block font-mono text-xs text-base-content/50 break-all">{{
                target.id
              }}</span></a
            >
          </li>
        </ul>
        <p v-if="!catalog.targets.entries.length" class="text-xs text-base-content/60">
          No matching endpoints.
        </p>
        <nav class="flex gap-3 text-sm" aria-label="Target pages">
          <a
            v-if="catalog.query.target_after"
            :href="href({ target_after: '' })"
            @click="follow($event, href({ target_after: '' }))"
            >First page</a
          ><a
            v-if="catalog.targets.next_after"
            id="stage-targets-next"
            :href="href({ target_after: catalog.targets.next_after })"
            @click="follow($event, href({ target_after: catalog.targets.next_after }))"
            >Next 25 targets →</a
          >
        </nav>
      </section>
      <section class="border border-base-300 bg-base-100 p-4 space-y-3" aria-label="Choose command">
        <h3 class="text-sm font-semibold">Command</h3>
        <form id="stage-command-search" class="flex gap-2" @submit.prevent="search('command')">
          <input
            id="stage-command-query"
            v-model="searches.command_query"
            aria-label="Search commands"
            class="input input-bordered input-sm min-w-0 flex-1"
            maxlength="240"
          /><button class="btn btn-ghost btn-sm" :disabled="disabled">Search</button>
        </form>
        <p v-if="catalog.selected_command" class="text-xs text-info">
          Selected: {{ catalog.selected_command.display_name || catalog.selected_command.name }}
        </p>
        <p
          id="stage-command-unsupported"
          v-if="catalog.selected_command && !catalog.selected_command.supported"
          class="text-xs text-warning"
        >
          This command cannot be prepared with its current definition. Choose another command or
          update the mission model.
        </p>
        <p
          v-else-if="catalog.query.command && !catalog.selected_command"
          class="text-xs text-warning"
        >
          The selected command is unavailable in this model.
        </p>
        <ul id="stage-commands" class="divide-y divide-base-300">
          <li v-for="command in catalog.commands.entries" :key="command.id">
            <a
              :href="href({ command: command.id })"
              class="block py-3 text-sm hover:text-info"
              @click="follow($event, href({ command: command.id }))"
              >{{ command.display_name || command.name
              }}<span class="block font-mono text-xs text-base-content/50 break-all">{{
                command.id
              }}</span></a
            >
          </li>
        </ul>
        <p v-if="!catalog.commands.entries.length" class="text-xs text-base-content/60">
          No matching commands.
        </p>
        <nav class="flex gap-3 text-sm" aria-label="Command pages">
          <a
            v-if="catalog.query.command_after"
            :href="href({ command_after: '' })"
            @click="follow($event, href({ command_after: '' }))"
            >First page</a
          ><a
            v-if="catalog.commands.next_after"
            id="stage-commands-next"
            :href="href({ command_after: catalog.commands.next_after })"
            @click="follow($event, href({ command_after: catalog.commands.next_after }))"
            >Next 25 commands →</a
          >
        </nav>
      </section>
    </div>
    <form v-else id="stage-command-form" class="space-y-4" @submit.prevent="resolvePreview">
      <fieldset :disabled="disabled" class="space-y-4">
        <div class="border border-base-300 bg-base-100 p-4 space-y-2">
          <h3 class="font-semibold">
            {{ catalog.selected_command?.display_name || catalog.selected_command?.name }}
          </h3>
          <p class="text-sm">
            Target: {{ catalog.selected_target?.name || catalog.selected_target?.id }}
          </p>
          <p
            v-if="catalog.selected_command?.hazardous || catalog.selected_command?.critical"
            class="text-sm text-warning"
          >
            {{ catalog.selected_command.hazardous ? "Hazardous" : "Critical" }} command. Review its
            resolved arguments before saving the draft.
          </p>
          <a
            :href="href({ command: '', target: '' })"
            class="text-xs underline"
            @click="follow($event, href({ command: '', target: '' }))"
            >Choose a different target or command</a
          >
        </div>
        <CommandArguments
          ref="controls"
          :arguments="catalog.selected_command?.arguments ?? []"
          v-bind="supplied === undefined ? {} : { supplied }"
          id-prefix="stage-command"
          @edited="edited"
        />
        <div class="grid gap-3 md:grid-cols-3">
          <label class="block space-y-1 text-sm"
            >Priority<select
              id="stage-command-priority"
              v-model="form.priority"
              class="select select-bordered w-full"
              @change="edited"
            >
              <option
                v-for="choice in priorityChoices(item?.priority)"
                :key="choice.rank"
                :value="String(choice.rank)"
              >
                {{ choice.label }}
              </option>
            </select></label
          ><label class="block space-y-1 text-sm"
            >Not before (UTC)<input
              id="stage-command-not-before"
              v-model="form.notBefore"
              placeholder="YYYY-MM-DDTHH:MM:SSZ"
              class="input input-bordered w-full"
              @input="edited" /></label
          ><label class="block space-y-1 text-sm"
            >Expires at (UTC)<input
              id="stage-command-expires-at"
              v-model="form.expiresAt"
              placeholder="YYYY-MM-DDTHH:MM:SSZ"
              class="input input-bordered w-full"
              @input="edited"
          /></label>
        </div>
        <button id="stage-command-preview" class="btn btn-ghost" :disabled="disabled">
          Preview draft
        </button>
      </fieldset>
    </form>
    <section
      v-if="preview"
      id="stage-item-preview"
      class="border border-info/30 bg-base-100 p-4 space-y-4"
      aria-label="Resolved draft preview"
    >
      <h3 class="font-semibold">Resolved draft</h3>
      <p class="text-sm">
        {{ preview.command.command_display_name || preview.command.command_name }} →
        {{ preview.command.target.name || preview.command.target.id }}
      </p>
      <dl class="grid gap-2 text-sm">
        <div
          v-for="(value, name) in parseArgumentValues(
            preview.command.resolved_argument_values_json,
            131072,
          )"
          :key="name"
          class="flex flex-wrap justify-between gap-2 border-b border-base-300 py-1"
        >
          <dt>{{ name }}</dt>
          <dd class="font-mono break-all">{{ value }}</dd>
        </div>
      </dl>
      <p class="text-xs text-base-content/60">
        Priority {{ priorityLabel(preview.command.priority) }} · Not before
        {{ preview.command.not_before || "No restriction" }} · Expires
        {{ preview.command.expires_at || "No expiry" }}
      </p>
      <div class="grid gap-3 md:grid-cols-[1fr_8rem]">
        <label class="block space-y-1 text-sm"
          >Draft notes<textarea
            id="stage-item-authoring-notes"
            v-model="form.notes"
            :disabled="disabled"
            maxlength="4000"
            rows="3"
            class="textarea textarea-bordered w-full"
          /></label
        ><label class="block space-y-1 text-sm"
          >Order<input
            id="stage-item-authoring-order"
            v-model="form.order"
            :disabled="disabled"
            inputmode="numeric"
            class="input input-bordered w-full"
        /></label>
      </div>
      <button id="stage-item-save" class="btn btn-primary" :disabled="disabled" @click="save">
        {{ preview.new ? "Add draft to stage" : "Save draft command" }}
      </button>
      <p class="text-xs text-base-content/60">
        Saving a draft does not create, approve, queue, or release a command request.
      </p>
    </section>
  </section>
</template>
