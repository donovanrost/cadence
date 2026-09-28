<script setup lang="ts">
import { computed, ref, watch } from "vue";
import CadencePane from "@cadence/ui/CadencePane.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import {
  StageBatchPreview,
  type BatchPreview,
  type Item,
  type Workbench,
  type WorkbenchQuery,
} from "@cadence/commanding/stage-workbench";
import { commandReviewHref } from "@cadence/commanding/command-review";
import { stagesHref } from "@cadence/commanding/command-stages";
import { priorityLabel } from "../../shared/priority";
import { parseArgumentValues } from "../../shared/command-draft/exact-values";
import type { WorkspaceOperation } from "./contracts";
const props = defineProps<{
  mission: string;
  workbench: Workbench | null;
  selection: Readonly<Record<string, string>>;
  preview: BatchPreview | null;
  confirmed: boolean;
  operation: Exclude<WorkspaceOperation, { event: "enqueue" }> | null;
  checkingResult: boolean;
  disabled: boolean;
  actionDisabled: boolean;
  reviewing: boolean;
  targetNames: Readonly<Record<string, string>>;
  commandNames: Readonly<Record<string, string>>;
  follow: (event: MouseEvent, href: string) => void;
}>();
const emit = defineEmits<{
  "update:confirmed": [value: boolean];
  choose: [item: Item];
  browse: [query: Partial<WorkbenchQuery>];
  review: [];
  submit: [];
  minimize: [];
  "check-result": [];
  cancel: [item: Item];
  move: [item: Item, order: number];
}>();
const cancelId = ref<string | null>(null),
  itemOrder = ref("");
watch(
  () => props.workbench?.selected_item,
  (item, previous) => {
    if (
      item?.id !== previous?.id ||
      (item?.order !== previous?.order && itemOrder.value === String(previous?.order ?? 0))
    )
      itemOrder.value = String(item?.order ?? 0);
    if (item?.expected_item !== previous?.expected_item) cancelId.value = null;
  },
  { immediate: true },
);
const orderValid = computed(
  () => /^(0|[1-9]\d*)$/.test(itemOrder.value) && Number(itemOrder.value) <= 2147483647,
);
const label = (value: string) => value.replaceAll("_", " ");
</script>
<template>
  <CadencePane id="command-workspace-shelf" :title="workbench?.stage.name || 'Command stages'">
    <template #title><slot name="stage-picker" /></template>
    <template #actions>
      <CadenceButton
        size="xs"
        variant="quiet"
        aria-label="Minimize command shelf"
        @click="emit('minimize')"
        ><span class="hero-minus cw-icon" aria-hidden="true" /></CadenceButton
    ></template>
    <div v-if="operation" id="workspace-write-result" class="cw-receipt" role="status">
      <template v-if="operation.status === 'unconfirmed'"
        ><strong>Write result unconfirmed</strong
        ><span>Check the saved result without repeating this action.</span
        ><CadenceButton
          id="workspace-check-result"
          size="xs"
          variant="outline"
          :disabled="checkingResult"
          :loading="checkingResult"
          @click="emit('check-result')"
          >Check result</CadenceButton
        ><a
          v-if="operation.stage_id"
          :href="stagesHref(mission, operation.stage_id)"
          @click="follow($event, stagesHref(mission, operation.stage_id))"
          >Inspect stage</a
        ></template
      >
      <template v-else-if="operation.status === 'rejected'"
        ><strong>Change not saved</strong><span>{{ operation.feedback }}</span></template
      >
      <template v-else-if="operation.receipt.kind === 'requests'"
        ><strong>{{ operation.receipt.requests.length }} formal requests created</strong
        ><a
          v-for="request in operation.receipt.requests"
          :key="request.request_id"
          :data-workspace-request="request.request_id"
          :href="commandReviewHref(mission, request.request_id)"
          @click="follow($event, commandReviewHref(mission, request.request_id))"
          >{{ label(request.state) }} · Review request
          <span class="hero-arrow-up-right cw-small-icon" aria-hidden="true" /></a
      ></template>
      <template v-else-if="operation.receipt.kind === 'drafts'"
        ><strong>{{ operation.receipt.items.length }} drafts saved</strong
        ><span>Ready for request review.</span></template
      >
      <template v-else-if="operation.receipt.kind === 'stage'"
        ><strong>{{ operation.receipt.name }} created</strong
        ><span>Prepare commands for this stage.</span></template
      >
      <template v-else><strong>Draft updated</strong></template>
    </div>
    <div v-if="workbench" class="cw-inline-actions">
      <span class="cw-subtle"
        >{{ workbench.stage.visibility }} · {{ label(workbench.stage.state) }}</span
      ><a
        :href="stagesHref(mission, workbench.stage.id)"
        @click="follow($event, stagesHref(mission, workbench.stage.id))"
        >Stage settings & history</a
      >
      <div class="cw-actions">
        <CadenceButton
          v-for="state in ['', 'draft', 'submitted', 'canceled']"
          :key="state"
          size="xs"
          :variant="workbench.query.state === state ? 'outline' : 'quiet'"
          :disabled="disabled"
          @click="emit('browse', { state, after: '', after_order: '', item: '' })"
          >{{ state ? label(state) : "All" }}</CadenceButton
        >
      </div>
    </div>
    <div v-if="workbench?.items.entries.length" class="cw-table-scroll">
      <table class="cw-table">
        <thead>
          <tr>
            <th scope="col"><span class="sr-only">Select draft</span></th>
            <th scope="col">Order</th>
            <th scope="col">Command</th>
            <th scope="col">Target</th>
            <th scope="col">Priority</th>
            <th scope="col">State</th>
            <th scope="col"><span class="sr-only">Draft actions</span></th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="item in workbench.items.entries"
            :key="item.id"
            :data-workspace-item="item.id"
            :aria-selected="workbench.selected_item?.id === item.id"
          >
            <td>
              <input
                v-if="item.state === 'draft' && item.available && workbench.stage.can_edit_items"
                type="checkbox"
                class="checkbox checkbox-xs"
                :aria-label="`Select draft ${commandNames[item.command_id] || item.command_id} at order ${item.order}`"
                :checked="Object.hasOwn(selection, item.id)"
                :disabled="disabled"
                @change="emit('choose', item)"
              />
            </td>
            <td class="cw-mono">{{ item.order }}</td>
            <td>
              <button
                type="button"
                class="cw-text-button"
                :disabled="disabled"
                @click="emit('browse', { item: item.id })"
              >
                {{ commandNames[item.command_id] || item.command_id }}
              </button>
            </td>
            <td>{{ item.target_name || targetNames[item.target_id] || "Unnamed target" }}</td>
            <td>{{ priorityLabel(item.priority) }}</td>
            <td>
              <span class="cw-state"
                ><span
                  :class="
                    item.state === 'submitted'
                      ? 'hero-arrow-right-circle'
                      : item.state === 'draft'
                        ? 'hero-pencil-square'
                        : 'hero-x-circle'
                  "
                  class="cw-small-icon"
                  aria-hidden="true"
                />{{ label(item.state) }}</span
              ><span v-if="!item.available" class="cw-notice">Content unavailable</span>
            </td>
            <td>
              <a
                v-if="item.request_id"
                :href="commandReviewHref(mission, item.request_id)"
                @click="follow($event, commandReviewHref(mission, item.request_id))"
                >Review request →</a
              ><template v-else-if="item.state === 'draft' && workbench.stage.can_edit_items"
                ><CadenceButton
                  v-if="cancelId !== item.id"
                  size="xs"
                  variant="quiet"
                  :disabled="disabled"
                  :aria-label="`Remove draft at order ${item.order}`"
                  @click="cancelId = item.id"
                  ><span class="hero-x-mark cw-small-icon" aria-hidden="true" /></CadenceButton
                ><template v-else
                  ><CadenceButton
                    size="xs"
                    variant="danger"
                    :disabled="disabled || actionDisabled"
                    @click="emit('cancel', item)"
                    >Cancel draft</CadenceButton
                  ><CadenceButton size="xs" variant="quiet" @click="cancelId = null"
                    >Keep</CadenceButton
                  ></template
                ></template
              >
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-else class="cw-empty cw-shelf-empty">
      <span class="hero-queue-list cw-empty-icon" aria-hidden="true" />
      <p>
        {{
          workbench
            ? "No drafts in this view. Prepare a command above to add it to the stage."
            : "Choose or create a stage to build a command sequence."
        }}
      </p>
    </div>
    <div v-if="workbench?.selected_item" class="cw-item-inspector">
      <div class="cw-actions">
        <strong>{{
          commandNames[workbench.selected_item.command_id] || workbench.selected_item.command_id
        }}</strong
        ><CadenceButton size="xs" variant="quiet" @click="emit('browse', { item: '' })"
          >Close details</CadenceButton
        >
      </div>
      <dl v-if="workbench.selected_item.argument_values_json" class="cw-arguments">
        <div
          v-for="(value, name) in parseArgumentValues(workbench.selected_item.argument_values_json)"
          :key="name"
        >
          <dt>{{ name }}</dt>
          <dd>{{ value }}</dd>
        </div>
      </dl>
      <p v-if="workbench.selected_item.notes" class="cw-description">
        {{ workbench.selected_item.notes }}
      </p>
      <div
        v-if="workbench.selected_item.state === 'draft' && workbench.stage.can_edit_items"
        class="cw-actions"
      >
        <label for="workspace-draft-order">Order</label
        ><input
          id="workspace-draft-order"
          v-model="itemOrder"
          class="input input-sm cw-order"
          inputmode="numeric"
          :disabled="disabled"
        /><CadenceButton
          size="xs"
          variant="outline"
          :disabled="
            disabled ||
            actionDisabled ||
            !orderValid ||
            Number(itemOrder) === workbench.selected_item.order
          "
          @click="emit('move', workbench.selected_item, Number(itemOrder))"
          >Save order</CadenceButton
        >
      </div>
      <details class="cw-disclosure">
        <summary>Draft evidence</summary>
        <dl class="cw-evidence">
          <dt>Model</dt>
          <dd>{{ workbench.selected_item.revision_id }}</dd>
          <dt>Target</dt>
          <dd>{{ workbench.selected_item.target_id }}</dd>
          <dt>Draft</dt>
          <dd>{{ workbench.selected_item.id }}</dd>
        </dl>
      </details>
    </div>
    <StageBatchPreview
      v-if="preview"
      :preview="preview"
      :confirmed="confirmed"
      :disabled="disabled || actionDisabled"
      @update:confirmed="emit('update:confirmed', $event)"
      @submit="emit('submit')"
    />
    <template #footer
      ><div class="cw-actions">
        <CadenceButton
          v-if="workbench?.stage.can_edit_items"
          id="workspace-review-stage"
          size="sm"
          variant="primary"
          :disabled="disabled || reviewing || !Object.keys(selection).length"
          @click="emit('review')"
          >Review {{ Object.keys(selection).length }} selected drafts</CadenceButton
        ><CadenceButton
          v-if="workbench?.query.after"
          size="xs"
          variant="quiet"
          :disabled="disabled"
          @click="emit('browse', { after: '', after_order: '', item: '' })"
          >First page</CadenceButton
        ><CadenceButton
          v-if="workbench?.items.next_after"
          size="xs"
          variant="quiet"
          :disabled="disabled"
          @click="
            emit('browse', {
              after: workbench.items.next_after.id,
              after_order: String(workbench.items.next_after.order),
              item: '',
            })
          "
          >Next 25 drafts →</CadenceButton
        >
      </div>
      <span v-if="workbench"
        >Updated · {{ workbench.observed_at.slice(11, 19) }} UTC</span
      ></template
    >
  </CadencePane>
</template>
