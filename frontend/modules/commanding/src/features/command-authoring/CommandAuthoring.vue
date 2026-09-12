<script setup lang="ts">
import { formatArgumentValues } from "../../shared/command-draft/exact-values";
import { priorityChoices, priorityLabel } from "../../shared/priority";
import { computed, onBeforeUnmount, reactive, ref, shallowRef } from "vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";
import CadenceOpsListBodyFrame from "@cadence/ui/CadenceOpsListBodyFrame.vue";
import CommandArguments from "../../shared/command-draft/CommandArguments.vue";
import { commandReviewHref } from "@cadence/commanding/command-review";
import {
  authoringHref,
  previewInput,
  readAuthoringPage,
  readOperation,
  readPreviewResult,
  type AuthoringPage,
  type Operation,
  type Preview,
  type Query,
} from "./contracts";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ page: AuthoringPage; port: OpsPagePort; readPort: OpsPageReadPort }>();
const catalog = shallowRef(props.page.catalog),
  preview = shallowRef<Preview | null>(props.page.preview),
  operation = shallowRef<Operation | null>(props.page.operation);
const context = { ...props.page.catalog.context },
  actor = props.page.catalog.actor_id;
const busy = ref(false),
  reading = ref(false),
  feedback = ref(""),
  confirmed = ref(false);
const priority = ref("3"),
  notBefore = ref(""),
  expiresAt = ref("");
const argumentControls = ref<InstanceType<typeof CommandArguments> | null>(null);
const searches = reactive({
  target_query: catalog.value.query.target_query,
  command_query: catalog.value.query.command_query,
});
const command = computed(() => catalog.value.selected_command),
  target = computed(() => catalog.value.selected_target);
const ready = computed(() => !!command.value?.supported && !!target.value),
  locked = computed(() => busy.value || reading.value || !!operation.value);
const monitor = `/missions/${encodeURIComponent(context.missionId)}/ops/commands`;
let disposed = false;
const disposeGuard = props.port.guardNavigation?.(() => !busy.value && !reading.value);
onBeforeUnmount(() => {
  disposed = true;
  disposeGuard?.();
});
function initialize() {
  argumentControls.value?.initialize(preview.value?.argument_values_json);
}
function edited() {
  if (!operation.value) {
    preview.value = null;
    confirmed.value = false;
    feedback.value = "";
  }
}
async function resolvePreview() {
  if (locked.value || !ready.value) return;
  let input;
  try {
    input = previewInput(
      catalog.value,
      argumentControls.value?.collect() ?? "{}",
      priority.value,
      notBefore.value,
      expiresAt.value,
    );
  } catch (error) {
    feedback.value =
      error instanceof Error && !error.message.startsWith("Unavailable")
        ? error.message
        : "Check priority, UTC timing and argument values before previewing.";
    return;
  }
  busy.value = true;
  preview.value = null;
  confirmed.value = false;
  feedback.value = "";
  try {
    const result = readPreviewResult(await props.port.execute("preview", input), catalog.value);
    if (!disposed) {
      if (result.status === "previewed") preview.value = result.preview;
      else feedback.value = result.feedback;
    }
  } catch {
    if (!disposed)
      feedback.value =
        "The preview could not be confirmed. Refresh the model or try previewing again.";
  } finally {
    if (!disposed) busy.value = false;
  }
}
async function create() {
  if (locked.value || !preview.value || !confirmed.value) return;
  const captured = preview.value;
  busy.value = true;
  feedback.value = "";
  operation.value = { status: "unconfirmed" };
  try {
    const result = readOperation(
      await props.port.execute("create", { expected_preview: captured.token }),
      captured,
    );
    if (!disposed) operation.value = result;
  } catch {
    /* A create attempt is consumed; only a read can recover its receipt. */
  } finally {
    if (!disposed) busy.value = false;
  }
}
async function refresh() {
  if (busy.value || reading.value) return;
  reading.value = true;
  feedback.value = "";
  try {
    const result = readAuthoringPage(await props.readPort.read(), context);
    if (result.catalog.actor_id !== actor) throw Error("Changed actor");
    if (!disposed) {
      const changed = result.catalog.basis.token !== catalog.value.basis.token;
      catalog.value = result.catalog;
      if (result.operation && result.preview) {
        preview.value = result.preview;
        operation.value = result.operation;
      } else if (!operation.value) {
        if (changed) {
          preview.value = null;
          initialize();
          confirmed.value = false;
          feedback.value =
            "The active model changed. Review the command and arguments, then create a new preview.";
        } else if (preview.value?.token !== result.preview?.token) {
          preview.value = null;
          confirmed.value = false;
        }
      }
    }
  } catch {
    if (!disposed)
      feedback.value = operation.value
        ? "The receipt is still unconfirmed. This request will not be submitted again."
        : "The catalog could not be refreshed. The last observed model remains visible.";
  } finally {
    if (!disposed) reading.value = false;
  }
}
function href(changes: Partial<Query>) {
  return authoringHref(context.missionId, { ...catalog.value.query, ...changes });
}
function follow(event: MouseEvent, url: string) {
  if (event.button !== 0 || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey)
    return;
  event.preventDefault();
  if (!busy.value && !reading.value) props.port.navigate(url);
}
function search(kind: "target" | "command") {
  if (locked.value) return;
  props.port.navigate(
    href(
      kind === "target"
        ? { target_query: searches.target_query, target_after: "" }
        : { command_query: searches.command_query, command_after: "" },
    ),
  );
}
const format = (value: unknown) =>
  value === null
    ? "Not recorded"
    : typeof value === "object"
      ? JSON.stringify(value, null, 2)
      : String(value);
</script>
<template>
  <CadenceOpsViewport id="command-authoring">
    <CadencePageHeading>
      <template #eyebrow>{{ catalog.mission_name }} / Commanding</template>
      <template #title>Create command request</template>
      <template #description
        >Choose a target and command, then review the resolved request. Approval and release are
        separate steps.</template
      >
      <template #actions
        ><a
          id="command-authoring-back"
          :href="monitor"
          class="btn btn-ghost btn-sm"
          @click="follow($event, monitor)"
          >Return to Commands</a
        ></template
      >
    </CadencePageHeading>
    <CadenceOpsListBodyFrame>
      <div class="flex flex-wrap items-center justify-between gap-3 text-xs text-base-content/70">
        <p>
          Observed model
          <span id="authoring-model-revision" class="font-mono break-all">{{
            catalog.basis.revision_id
          }}</span>
          · Generation {{ catalog.basis.generation }}
        </p>
        <button
          id="command-authoring-refresh"
          class="btn btn-ghost btn-sm"
          :disabled="busy || reading"
          @click="refresh"
        >
          {{ reading ? "Refreshing…" : "Refresh model and receipt" }}
        </button>
      </div>
      <p v-if="feedback" id="command-authoring-feedback" role="alert" class="text-sm text-warning">
        {{ feedback }}
      </p>
      <div v-if="!ready && !operation" class="grid gap-4 lg:grid-cols-2">
        <section
          class="min-w-0 border border-base-300 bg-base-100 p-4 space-y-4"
          aria-labelledby="authoring-target-title"
        >
          <h2 id="authoring-target-title" class="font-semibold">1. Target endpoint</h2>
          <form id="authoring-target-search" class="flex gap-2" @submit.prevent="search('target')">
            <input
              id="authoring-target-query"
              v-model="searches.target_query"
              aria-label="Search target endpoints"
              class="input input-bordered input-sm min-w-0 flex-1"
              maxlength="240"
            /><button class="btn btn-ghost btn-sm" :disabled="locked">Search</button>
          </form>
          <p v-if="target" class="text-sm text-info">Selected: {{ target.name || target.id }}</p>
          <p v-else-if="catalog.query.target" class="text-sm text-warning">
            The selected endpoint is unavailable. Choose a current target.
          </p>
          <ul id="authoring-targets" class="divide-y divide-base-300">
            <li v-for="item in catalog.targets.entries" :key="item.id">
              <a
                :href="href({ target: item.id })"
                class="block py-3 space-y-1 hover:text-info"
                :aria-current="item.id === catalog.query.target ? 'true' : undefined"
                @click="follow($event, href({ target: item.id }))"
                ><span class="block font-medium text-sm">{{ item.name || item.id }}</span
                ><span class="block font-mono text-xs break-all text-base-content/60"
                  >{{ item.id }} · SCID {{ item.scid ?? "Not recorded" }}</span
                ></a
              >
            </li>
          </ul>
          <p v-if="!catalog.targets.entries.length" class="text-sm text-base-content/60">
            No matching target endpoints.
          </p>
          <div class="flex gap-3 text-sm">
            <a
              v-if="catalog.query.target_after"
              :href="href({ target_after: '' })"
              @click="follow($event, href({ target_after: '' }))"
              >First page</a
            ><a
              v-if="catalog.targets.next_after"
              id="authoring-targets-next"
              :href="href({ target_after: catalog.targets.next_after })"
              @click="follow($event, href({ target_after: catalog.targets.next_after }))"
              >Next 25 targets →</a
            >
          </div>
        </section>
        <section
          class="min-w-0 border border-base-300 bg-base-100 p-4 space-y-4"
          aria-labelledby="authoring-command-title"
        >
          <h2 id="authoring-command-title" class="font-semibold">2. Command</h2>
          <form
            id="authoring-command-search"
            class="flex gap-2"
            @submit.prevent="search('command')"
          >
            <input
              id="authoring-command-query"
              v-model="searches.command_query"
              aria-label="Search commands"
              class="input input-bordered input-sm min-w-0 flex-1"
              maxlength="240"
            /><button class="btn btn-ghost btn-sm" :disabled="locked">Search</button>
          </form>
          <p v-if="command" class="text-sm text-info">
            Selected: {{ command.display_name || command.name }}
          </p>
          <p v-else-if="catalog.query.command" class="text-sm text-warning">
            The selected command is unavailable in this model. Choose a current command.
          </p>
          <p
            id="authoring-command-unsupported"
            v-if="command && !command.supported"
            role="alert"
            class="text-sm text-warning"
          >
            This command cannot be prepared with its current definition. Choose another command or
            update the mission model.
          </p>
          <ul id="authoring-commands" class="divide-y divide-base-300">
            <li v-for="item in catalog.commands.entries" :key="item.id">
              <a
                :href="href({ command: item.id })"
                class="block py-3 space-y-1 hover:text-info"
                :aria-current="item.id === catalog.query.command ? 'true' : undefined"
                @click="follow($event, href({ command: item.id }))"
                ><span class="block font-medium text-sm">{{ item.display_name || item.name }}</span
                ><span class="block font-mono text-xs break-all text-base-content/60">{{
                  item.id
                }}</span></a
              >
            </li>
          </ul>
          <p v-if="!catalog.commands.entries.length" class="text-sm text-base-content/60">
            No matching commands.
          </p>
          <div class="flex gap-3 text-sm">
            <a
              v-if="catalog.query.command_after"
              :href="href({ command_after: '' })"
              @click="follow($event, href({ command_after: '' }))"
              >First page</a
            ><a
              v-if="catalog.commands.next_after"
              id="authoring-commands-next"
              :href="href({ command_after: catalog.commands.next_after })"
              @click="follow($event, href({ command_after: catalog.commands.next_after }))"
              >Next 25 commands →</a
            >
          </div>
        </section>
      </div>
      <form
        v-if="ready && !operation"
        id="command-authoring-form"
        class="space-y-4"
        @submit.prevent="resolvePreview"
      >
        <fieldset :disabled="locked" class="space-y-4">
          <section
            class="border border-base-300 bg-base-100 p-4 space-y-4"
            aria-labelledby="authoring-selected-title"
          >
            <div class="flex flex-wrap items-center justify-between gap-3">
              <h2 id="authoring-selected-title" class="font-semibold">
                {{ command?.display_name || command?.name }}
              </h2>
              <a
                id="authoring-change-selection"
                class="text-xs text-base-content/60 hover:text-info"
                :href="href({ command: '', target: '' })"
                @click="follow($event, href({ command: '', target: '' }))"
                >Choose a different target or command</a
              >
            </div>
            <p v-if="command?.description" class="text-sm text-base-content/70">
              {{ command.description }}
            </p>
            <p class="text-sm">
              Target: <strong>{{ target?.name || target?.id }}</strong> · SCID
              {{ target?.scid ?? "Not recorded" }}
            </p>
            <p class="font-mono text-xs break-all text-base-content/60">{{ target?.id }}</p>
            <p
              v-if="command?.hazardous || command?.critical"
              id="authoring-criticality"
              class="border-l-2 border-warning pl-3 text-sm text-warning"
            >
              {{ command.hazardous ? "Hazardous command" : "Critical command" }}. Review the
              resolved arguments and timing before creating the request.
            </p>
          </section>
          <CommandArguments
            ref="argumentControls"
            :arguments="command?.arguments ?? []"
            :supplied="preview?.argument_values_json"
            id-prefix="authoring"
            heading="3. Arguments"
            @edited="edited"
          />
          <section
            class="border border-base-300 bg-base-100 p-4 space-y-4"
            aria-labelledby="authoring-timing-title"
          >
            <h2 id="authoring-timing-title" class="font-semibold">4. Priority and timing</h2>
            <div class="grid gap-4 lg:grid-cols-3">
              <label class="space-y-2 text-sm"
                ><span class="block">Priority</span
                ><select
                  id="authoring-priority"
                  v-model="priority"
                  class="select select-bordered w-full"
                  @change="edited"
                >
                  <option
                    v-for="choice in priorityChoices()"
                    :key="choice.rank"
                    :value="String(choice.rank)"
                  >
                    {{ choice.label }}
                  </option>
                </select></label
              ><label class="space-y-2 text-sm"
                ><span class="block">Not before (UTC)</span
                ><input
                  id="authoring-not-before"
                  v-model="notBefore"
                  placeholder="YYYY-MM-DDTHH:MM:SSZ"
                  class="input input-bordered w-full font-mono text-xs"
                  @input="edited" /></label
              ><label class="space-y-2 text-sm"
                ><span class="block">Expires at (UTC)</span
                ><input
                  id="authoring-expires-at"
                  v-model="expiresAt"
                  placeholder="YYYY-MM-DDTHH:MM:SSZ"
                  class="input input-bordered w-full font-mono text-xs"
                  @input="edited"
              /></label>
            </div>
            <p class="text-xs text-base-content/60">
              Blank timing fields mean no earliest time or expiry. Preview resolves defaults without
              saving a request.
            </p>
          </section>
          <button id="command-authoring-preview" type="submit" class="btn btn-primary">
            {{ busy ? "Preparing preview…" : "Preview command request" }}
          </button>
        </fieldset>
      </form>
      <section
        v-if="preview"
        id="command-authoring-preview-details"
        class="border border-base-300 bg-base-100 p-4 space-y-4"
        aria-labelledby="authoring-preview-title"
      >
        <div class="flex flex-wrap justify-between gap-3">
          <h2 id="authoring-preview-title" class="font-semibold">Review resolved request</h2>
          <span class="badge badge-outline">{{
            preview.lifecycle_state.replaceAll("_", " ")
          }}</span>
        </div>
        <dl class="grid gap-4 text-sm sm:grid-cols-2 lg:grid-cols-3">
          <div
            v-for="field in [
              ['Request ID', preview.request_id],
              ['Target endpoint', preview.target.id],
              ['SCID', preview.target.scid],
              ['Model revision', preview.revision_id],
              ['Command ID', preview.command_id],
              ['Requested by', preview.actor_id],
              ['Priority', priorityLabel(preview.priority)],
              ['Not before', preview.not_before],
              ['Expires at', preview.expires_at],
              ['Critical', preview.critical],
              ['Hazardous', preview.hazardous],
              ['Significance', preview.significance],
            ]"
            :key="String(field[0])"
            class="min-w-0"
          >
            <dt class="hud-label">{{ field[0] }}</dt>
            <dd class="mt-1 whitespace-pre-wrap break-all font-mono text-xs">
              {{ format(field[1]) }}
            </dd>
          </div>
        </dl>
        <div class="grid gap-4 lg:grid-cols-2">
          <div
            v-for="item in [
              {
                id: 'submitted',
                title: 'Submitted arguments',
                values: preview.argument_values_json,
              },
              {
                id: 'resolved',
                title: 'Resolved arguments',
                values: preview.resolved_argument_values_json,
              },
            ]"
            :key="item.id"
            class="min-w-0 space-y-2"
          >
            <h3 class="text-sm font-medium">{{ item.title }}</h3>
            <pre
              :id="`authoring-${item.id}-arguments`"
              class="whitespace-pre-wrap break-all font-mono text-xs"
              >{{ formatArgumentValues(item.values) }}</pre>
          </div>
        </div>
        <template v-if="!operation"
          ><label class="flex items-start gap-3 text-sm"
            ><input
              id="authoring-confirm"
              v-model="confirmed"
              type="checkbox"
              class="checkbox checkbox-sm"
              :disabled="locked"
            />I reviewed the target, arguments and timing.</label
          ><button
            id="command-authoring-create"
            class="btn btn-primary"
            :disabled="!confirmed || locked"
            @click="create"
          >
            Create command request
          </button></template
        >
      </section>
      <section
        v-if="operation && preview"
        id="command-authoring-result"
        role="status"
        class="border border-base-300 bg-base-100 p-4 space-y-3"
      >
        <template v-if="operation.status === 'completed'"
          ><h2 class="font-semibold">Command request saved</h2>
          <p class="text-sm">The persisted request is ready for its next workflow step.</p>
          <p class="font-mono text-xs break-all">{{ operation.receipt.request_id }}</p></template
        >
        <template v-else-if="operation.status === 'rejected'"
          ><h2 class="font-semibold">Request was not created</h2>
          <p class="text-sm">{{ operation.feedback }}</p></template
        >
        <template v-else
          ><h2 class="font-semibold">Creation is unconfirmed</h2>
          <p class="text-sm">
            Refresh the receipt or open the reserved request ID to check whether it was saved. This
            page will not submit it again.
          </p></template
        >
        <a
          id="authoring-open-request"
          class="btn btn-ghost btn-sm"
          :href="commandReviewHref(context.missionId, preview.request_id)"
          @click="follow($event, commandReviewHref(context.missionId, preview.request_id))"
          >Open request</a
        >
        <a
          v-if="operation.status !== 'unconfirmed'"
          id="authoring-start-new"
          class="btn btn-ghost btn-sm"
          :href="
            authoringHref(context.missionId, {
              command: '',
              target: '',
              command_after: '',
              target_after: '',
              command_query: '',
              target_query: '',
            })
          "
          @click="
            follow(
              $event,
              authoringHref(context.missionId, {
                command: '',
                target: '',
                command_after: '',
                target_after: '',
                command_query: '',
                target_query: '',
              }),
            )
          "
          >Start another request</a
        >
      </section>
    </CadenceOpsListBodyFrame>
  </CadenceOpsViewport>
</template>
