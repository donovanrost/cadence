<script setup lang="ts">
import { parseArgumentValues } from "../../shared/command-draft/exact-values";
import { computed, reactive, ref, watch } from "vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceOpsListBodyFrame from "@cadence/ui/CadenceOpsListBodyFrame.vue";
import { commandReviewHref } from "@cadence/commanding/command-review";
import { stagesHref } from "../../shared/stages/links";
import { order, text } from "../../shared/stages/validation";
import { emptyCatalogQuery, type WorkbenchPage } from "./contracts";
import { useStageWorkbench } from "./useStageWorkbench";
import StageCommandEditor from "./StageCommandEditor.vue";
import StageBatchPreview from "./StageBatchPreview.vue";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ page: WorkbenchPage; port: OpsPagePort; readPort: OpsPageReadPort }>();
const {
  page,
  workbench,
  context,
  busy,
  reading,
  feedback,
  operation,
  itemPreview,
  batchPreview,
  selection,
  batchConfirmed,
  locked,
  href,
  follow,
  choose,
  clearItemPreview,
  refresh,
  previewItem,
  previewBatch,
  write,
  saveItem,
  submit,
  restartDraft,
} = useStageWorkbench(props.page, props.port, props.readPort);
const stage = computed(() => workbench.value.stage),
  selected = computed(() => workbench.value.selected_item);
const stageForm = reactive({ name: "", description: "", visibility: "private", state: "draft" }),
  details = reactive({ notes: "", order: "0" }),
  confirmCancel = ref(false),
  confirmStageCancel = ref(false);
watch(
  () => stage.value.expected_stage,
  () => {
    Object.assign(stageForm, {
      name: stage.value.name,
      description: stage.value.description ?? "",
      visibility: stage.value.visibility,
      state: stage.value.state,
    });
    confirmStageCancel.value = false;
  },
  { immediate: true },
);
watch(
  () => selected.value?.expected_item,
  () => {
    details.notes = selected.value?.notes ?? "";
    details.order = String(selected.value?.order ?? 0);
    confirmCancel.value = false;
  },
  { immediate: true },
);
function navigate(url: string) {
  if (!busy.value && !reading.value) props.port.navigate(url);
}
async function editStage() {
  if (
    !stage.value.can_edit_stage ||
    locked.value ||
    (stageForm.state === "canceled" && !confirmStageCancel.value)
  )
    return;
  if (!text(stageForm.name, 240) || !stageForm.name.trim() || !text(stageForm.description, 4000)) {
    feedback.value = "Use a name up to 240 UTF-8 bytes and description up to 4,000 bytes.";
    return;
  }
  await write("edit_stage", {
    expected_stage: stage.value.expected_stage,
    ...stageForm,
    description: stageForm.description || null,
  });
}
async function editDetails() {
  if (!selected.value || !stage.value.can_edit_items || locked.value) return;
  if (
    !text(details.notes, 4000) ||
    !/^(0|[1-9]\d*)$/.test(details.order) ||
    !order(Number(details.order))
  ) {
    feedback.value = "Check the notes and nonnegative whole-number order.";
    return;
  }
  await write("edit_details", {
    expected_stage: stage.value.expected_stage,
    expected_item: selected.value.expected_item,
    notes: details.notes || null,
    order: Number(details.order),
  });
}
async function cancelItem() {
  if (!confirmCancel.value || !selected.value || locked.value) return;
  await write("cancel_item", {
    expected_stage: stage.value.expected_stage,
    expected_item: selected.value.expected_item,
  });
}
</script>
<template>
  <CadenceOpsViewport id="stage-workbench"
    ><CadencePageHeading
      ><template #eyebrow>{{ workbench.mission_name }} / Commanding</template
      ><template #title>{{ stage.name }}</template
      ><template #description>{{
        stage.description || "Prepare and review a finite batch of command drafts."
      }}</template
      ><template #actions
        ><a
          :href="stagesHref(context.missionId)"
          class="btn btn-ghost btn-sm"
          @click="follow($event, stagesHref(context.missionId))"
          >All stages</a
        ><button
          id="stage-workbench-refresh"
          class="btn btn-ghost btn-sm"
          :disabled="busy || reading"
          @click="refresh"
        >
          {{ reading ? "Refreshing…" : "Refresh stage and result" }}
        </button></template
      ></CadencePageHeading
    >
    <CadenceOpsListBodyFrame>
      <div class="flex flex-wrap justify-between gap-3 text-xs">
        <p class="flex gap-3">
          <strong>{{ stage.visibility === "private" ? "Private" : "Shared" }}</strong
          ><span>{{ stage.state.replaceAll("_", " ") }}</span>
        </p>
        <span class="font-mono break-all text-base-content/50">{{ stage.id }}</span>
      </div>
      <p v-if="feedback" id="stage-workbench-feedback" role="alert" class="text-sm text-warning">
        {{ feedback }}
      </p>
      <p v-if="page.notice" role="status" class="text-sm text-warning">{{ page.notice }}</p>
      <section
        v-if="operation"
        id="stage-workbench-result"
        aria-live="polite"
        class="border border-base-300 bg-base-100 p-4 space-y-2"
      >
        <template v-if="operation.status === 'completed'"
          ><h2 class="font-semibold">
            {{ operation.event === "submit" ? "Formal requests created" : "Stage change saved" }}
          </h2>
          <ul v-if="operation.receipt.requests" class="space-y-2 text-sm">
            <li v-for="request in operation.receipt.requests" :key="request.request_id">
              <a
                :data-created-request="request.request_id"
                :href="commandReviewHref(context.missionId, request.request_id)"
                class="font-mono break-all underline"
                @click="follow($event, commandReviewHref(context.missionId, request.request_id))"
                >{{ request.request_id }}</a
              ><span class="ml-2 text-base-content/60">{{
                request.state.replaceAll("_", " ")
              }}</span>
            </li>
          </ul>
          <p v-else-if="operation.receipt.item_id" class="font-mono break-all text-xs">
            {{ operation.receipt.item_id }}
          </p></template
        ><template v-else-if="operation.status === 'rejected'"
          ><h2 class="font-semibold">Change not saved</h2>
          <p class="text-sm">{{ operation.feedback }}</p></template
        ><template v-else
          ><h2 class="font-semibold">Write result unconfirmed</h2>
          <p class="text-sm">Refresh to check the result. This action will not be sent again.</p>
          <button
            v-if="operation.event !== 'submit'"
            id="stage-restart-draft"
            class="btn btn-ghost btn-sm"
            :disabled="busy || reading"
            @click="restartDraft"
          >
            Inspect current state and begin another draft edit
          </button></template
        >
      </section>
      <details v-if="stage.can_edit_stage" class="border border-base-300 bg-base-100 p-4">
        <summary class="cursor-pointer text-sm font-semibold">
          Stage name, visibility and state
        </summary>
        <form id="stage-settings-form" class="mt-4 space-y-3" @submit.prevent="editStage">
          <fieldset :disabled="locked" class="space-y-3">
            <div class="grid gap-3 md:grid-cols-2">
              <label class="block text-sm space-y-1"
                >Name<input
                  id="stage-settings-name"
                  v-model="stageForm.name"
                  maxlength="240"
                  required
                  class="input input-bordered w-full" /></label
              ><label class="block text-sm space-y-1"
                >Visibility<select
                  id="stage-settings-visibility"
                  v-model="stageForm.visibility"
                  class="select select-bordered w-full"
                >
                  <option value="private">Private — owner only</option>
                  <option value="shared">Shared — mission managers</option>
                </select></label
              >
            </div>
            <label class="block text-sm space-y-1"
              >Description<textarea
                id="stage-settings-description"
                v-model="stageForm.description"
                maxlength="4000"
                rows="3"
                class="textarea textarea-bordered w-full"
              /></label
            ><label class="block text-sm space-y-1"
              >Stage state<select
                id="stage-settings-state"
                v-model="stageForm.state"
                class="select select-bordered"
              >
                <option value="draft">Draft</option>
                <option value="in_review">In review</option>
                <option value="ready_to_submit">Ready to submit</option>
                <option value="canceled">Canceled</option>
              </select></label
            >
            <p class="text-xs text-base-content/60">
              Stage state describes preparation. Formal request approval is a separate workflow.
            </p>
            <label v-if="stageForm.state === 'canceled'" class="flex gap-2 text-sm"
              ><input
                id="stage-cancel-confirm"
                v-model="confirmStageCancel"
                type="checkbox"
                class="checkbox checkbox-sm"
              />Cancel this stage and close its drafts to further editing.</label
            ><button
              id="stage-settings-save"
              class="btn btn-ghost"
              :disabled="locked || (stageForm.state === 'canceled' && !confirmStageCancel)"
            >
              Save stage settings
            </button>
          </fieldset>
        </form>
      </details>
      <section aria-labelledby="stage-items-title" class="space-y-3">
        <div class="flex flex-wrap justify-between gap-3">
          <h2 id="stage-items-title" class="font-semibold">Stage items</h2>
          <a
            v-if="stage.can_edit_items"
            id="stage-new-item"
            :href="href({ item: '' }, emptyCatalogQuery())"
            class="btn btn-ghost btn-sm"
            @click="follow($event, href({ item: '' }, emptyCatalogQuery()))"
            >Add a command draft</a
          >
        </div>
        <nav class="flex flex-wrap gap-3 text-xs" aria-label="Filter stage items">
          <a
            v-for="state in ['', 'draft', 'submitted', 'canceled']"
            :key="state"
            :aria-current="workbench.query.state === state ? 'page' : undefined"
            :href="href({ state, after: '', after_order: '' })"
            @click="follow($event, href({ state, after: '', after_order: '' }))"
            >{{ state || "All items" }}</a
          >
        </nav>
        <ul id="stage-items" class="divide-y divide-base-300 border-y border-base-300">
          <li
            v-for="item in workbench.items.entries"
            :key="item.id"
            class="flex items-start gap-3 py-3"
          >
            <input
              v-if="stage.can_edit_items && item.state === 'draft' && item.available"
              type="checkbox"
              :data-select-item="item.id"
              :aria-label="`Select ${item.command_id} at order ${item.order}`"
              class="checkbox checkbox-sm mt-1"
              :disabled="locked"
              :checked="Object.hasOwn(selection, item.id)"
              @change="choose(item.id, ($event.target as HTMLInputElement).checked)"
            /><a
              :data-stage-item="item.id"
              :href="href({ item: item.id }, { command: item.command_id, target: item.target_id })"
              class="min-w-0 flex-1 space-y-1 hover:text-info"
              @click="
                follow(
                  $event,
                  href({ item: item.id }, { command: item.command_id, target: item.target_id }),
                )
              "
              ><span class="block text-sm font-medium"
                >{{ item.order }} · {{ item.command_id }}</span
              ><span class="block text-xs font-mono break-all text-base-content/50">{{
                item.id
              }}</span
              ><span v-if="!item.available" class="block text-xs text-warning"
                >Draft content is unavailable; inspect or cancel this item.</span
              ></a
            ><span class="text-xs text-base-content/60">{{ item.state }}</span>
          </li>
        </ul>
        <p
          v-if="!workbench.items.entries.length"
          id="stage-items-empty"
          class="py-4 text-sm text-base-content/60"
        >
          No items match this view.
        </p>
        <nav class="flex gap-4 text-sm" aria-label="Stage item pages">
          <a
            v-if="workbench.query.after"
            :href="href({ after: '', after_order: '' })"
            @click="follow($event, href({ after: '', after_order: '' }))"
            >First page</a
          ><a
            v-if="workbench.items.next_after"
            id="stage-items-next"
            :href="
              href({
                after: workbench.items.next_after.id,
                after_order: String(workbench.items.next_after.order),
              })
            "
            @click="
              follow(
                $event,
                href({
                  after: workbench.items.next_after.id,
                  after_order: String(workbench.items.next_after.order),
                }),
              )
            "
            >Next 25 items →</a
          >
        </nav>
        <div v-if="stage.can_edit_items" class="flex flex-wrap items-center gap-3">
          <button
            id="stage-preview-batch"
            class="btn btn-ghost"
            :disabled="locked || !Object.keys(selection).length"
            @click="previewBatch"
          >
            Preview {{ Object.keys(selection).length }} selected request{{
              Object.keys(selection).length === 1 ? "" : "s"
            }}</button
          ><span class="text-xs text-base-content/60"
            >Select up to 25 drafts on this page. Selection clears when the view changes.</span
          >
        </div>
      </section>
      <StageBatchPreview
        v-if="batchPreview"
        :preview="batchPreview"
        :disabled="locked"
        v-model:confirmed="batchConfirmed"
        @submit="submit"
      />
      <section
        v-if="selected"
        id="stage-selected-item"
        class="border border-base-300 bg-base-100 p-4 space-y-3"
        aria-labelledby="stage-selected-title"
      >
        <h2 id="stage-selected-title" class="font-semibold">
          Selected item · {{ selected.state }}
        </h2>
        <p class="font-mono break-all text-xs text-base-content/60">{{ selected.id }}</p>
        <p class="text-sm">
          {{ selected.command_id }} → {{ selected.target_name || "Unnamed target" }}
        </p>
        <p class="text-xs font-mono break-all text-base-content/50">
          Draft model: {{ selected.revision_id }}
        </p>
        <dl v-if="selected.available && selected.argument_values_json" class="text-sm">
          <div
            v-for="(value, name) in parseArgumentValues(selected.argument_values_json)"
            :key="name"
            class="flex flex-wrap justify-between gap-2"
          >
            <dt>{{ name }}</dt>
            <dd class="font-mono break-all">{{ value }}</dd>
          </div>
        </dl>
        <p v-else class="text-sm text-warning">
          The saved argument document exceeds this editor's supported bounds.
        </p>
        <a
          v-if="selected.request_id"
          id="stage-selected-request"
          :href="commandReviewHref(context.missionId, selected.request_id)"
          class="text-sm underline"
          @click="follow($event, commandReviewHref(context.missionId, selected.request_id))"
          >Open submitted request</a
        >
        <form
          v-if="stage.can_edit_items && selected.state === 'draft'"
          id="stage-item-details-form"
          class="space-y-3"
          @submit.prevent="editDetails"
        >
          <fieldset :disabled="locked" class="space-y-3">
            <div class="grid gap-3 md:grid-cols-[1fr_8rem]">
              <label class="block text-sm space-y-1"
                >Draft notes<textarea
                  id="stage-item-notes"
                  v-model="details.notes"
                  maxlength="4000"
                  rows="3"
                  class="textarea textarea-bordered w-full"
                /></label
              ><label class="block text-sm space-y-1"
                >Order<input
                  id="stage-item-order"
                  v-model="details.order"
                  inputmode="numeric"
                  class="input input-bordered w-full"
              /></label>
            </div>
            <button id="stage-item-details-save" class="btn btn-ghost" :disabled="locked">
              Save notes and order</button
            ><label class="flex gap-2 text-sm"
              ><input
                id="stage-item-cancel-confirm"
                v-model="confirmCancel"
                type="checkbox"
                class="checkbox checkbox-sm"
              />Cancel this draft item</label
            ><button
              id="stage-item-cancel"
              type="button"
              class="btn btn-ghost"
              :disabled="locked || !confirmCancel"
              @click="cancelItem"
            >
              Confirm cancellation
            </button>
          </fieldset>
        </form>
      </section>
      <p
        v-else-if="workbench.query.item"
        id="stage-selected-unavailable"
        role="status"
        class="text-sm text-warning"
      >
        The selected item is unavailable in this stage.
      </p>
      <template
        v-if="
          stage.can_edit_items &&
          (!workbench.query.item || (selected?.state === 'draft' && selected.available))
        "
        ><StageCommandEditor
          v-if="page.catalog"
          :key="`${page.catalog.basis.token}:${page.catalog.query.command}:${page.catalog.query.target}:${selected?.expected_item ?? 'new'}`"
          :catalog="page.catalog"
          :item="selected"
          :stage-token="stage.expected_stage"
          :disabled="locked"
          :preview="itemPreview"
          :href="(changes) => href({}, changes)"
          :follow="follow"
          @navigate="navigate"
          @edited="clearItemPreview"
          @preview="previewItem"
          @save="saveItem"
        />
        <p
          v-else
          id="stage-model-unavailable"
          role="status"
          class="border border-base-300 p-4 text-sm text-warning"
        >
          The active command model is unavailable. You can still inspect drafts, edit notes and
          order, or cancel items. Refresh when a command model is active.
        </p></template
      >
    </CadenceOpsListBodyFrame>
  </CadenceOpsViewport>
</template>
