<script setup lang="ts">
import { computed, reactive, ref, watch } from "vue";
import type { OpsPageContext, OpsPageNavigationPort } from "@cadence/plugin-sdk/ops-pages";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";
import CadenceOpsListBodyFrame from "@cadence/ui/CadenceOpsListBodyFrame.vue";
import CadenceOpsListFrame from "@cadence/ui/CadenceOpsListFrame.vue";
import CadenceDetailsFrame from "@cadence/ui/CadenceDetailsFrame.vue";
import CommandEvidence from "./CommandEvidence.vue";
import { commandHistoryHref } from "@cadence/commanding/command-history";
import { commandReviewHref } from "@cadence/commanding/command-review";
import { stagesHref } from "@cadence/commanding/command-stages";
import { authoringHref } from "@cadence/commanding/command-authoring";
import { commandStates, type CommandMonitorModel, type MonitorQuery } from "./monitor.contracts";
import { monitorHref } from "./monitor-query";
defineOptions({ inheritAttrs: false });
const props = defineProps<{
  model: CommandMonitorModel;
  context: OpsPageContext;
  port: OpsPageNavigationPort;
  refresh: () => Promise<void>;
}>();
const fields = reactive({ ...props.model.query }),
  pending = ref(false),
  filterError = ref(false);
watch(
  () => [props.model, props.port],
  () => {
    Object.assign(fields, props.model.query);
    pending.value = false;
    filterError.value = false;
  },
);
const currentPage = computed(() => Number(props.model.query.page));
const label = (value: string) => value.replaceAll("_", " ");
function href(query: MonitorQuery) {
  return monitorHref(props.model.mission_id, query);
}
function navigate(query: MonitorQuery) {
  if (pending.value) return;
  let destination: string;
  try {
    destination = href(query);
  } catch {
    filterError.value = true;
    return;
  }
  filterError.value = false;
  pending.value = true;
  props.port.navigate(destination);
}
function openStages(event: MouseEvent) {
  if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
    return;
  event.preventDefault();
  if (!pending.value) props.port.navigate(stagesHref(props.model.mission_id));
}
function follow(event: MouseEvent, id: string) {
  if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
    return;
  event.preventDefault();
  navigate({ ...props.model.query, focus_command_id: id });
}
function historyHref(id: string): string | undefined {
  try {
    return commandHistoryHref(props.model.mission_id, id);
  } catch {
    return undefined;
  }
}
function openHistory(event: MouseEvent, id: string) {
  if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
    return;
  event.preventDefault();
  const destination = historyHref(id);
  if (!pending.value && destination) props.port.navigate(destination);
}
function reviewHref(id: string): string | undefined {
  if (!props.model.can_review) return undefined;
  try {
    return commandReviewHref(props.model.mission_id, id);
  } catch {
    return undefined;
  }
}
function reviewRequest(event: MouseEvent, id: string) {
  if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
    return;
  event.preventDefault();
  const destination = reviewHref(id);
  if (!pending.value && destination) props.port.navigate(destination);
}
const createHref = computed(() => {
  if (!props.model.can_review) return undefined;
  try {
    return authoringHref(props.model.mission_id, {
      command: "",
      target: "",
      command_after: "",
      target_after: "",
      command_query: "",
      target_query: "",
    });
  } catch {
    return undefined;
  }
});
function createRequest(event: MouseEvent) {
  if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
    return;
  event.preventDefault();
  if (!pending.value && createHref.value) props.port.navigate(createHref.value);
}
function clearFocus() {
  const { focus_command_id: _, ...query } = props.model.query;
  navigate(query);
}
async function retry() {
  if (pending.value) return;
  pending.value = true;
  try {
    await props.refresh();
  } catch {
    /* The host owns refresh failure containment. */
  } finally {
    pending.value = false;
  }
}
</script>
<template>
  <CadenceOpsViewport id="command-monitor">
    <CadencePageHeading>
      <template #title>Commands</template>
      <template #eyebrow>Mission operations / command posture</template>
      <template #description
        >Request, queue, release and verifier evidence. Open a request for detailed
        review.</template
      >
      <template #actions>
        <a
          v-if="model.can_review"
          id="command-monitor-stages"
          :href="stagesHref(model.mission_id)"
          class="btn btn-ghost btn-sm"
          @click="openStages"
          >Command stages</a
        >
        <a
          v-if="createHref"
          id="command-monitor-create"
          :href="createHref"
          class="btn btn-primary btn-sm"
          @click="createRequest"
          >Create request</a
        >
        <div
          id="command-monitor-summary"
          class="grid grid-cols-2 gap-px border border-base-300 bg-base-300 sm:grid-cols-4"
          :data-command-active-count="model.summary.active_count"
        >
          <div
            v-for="metric in [
              { label: 'Queued', value: model.summary.queued_count },
              { label: 'Release pending', value: model.summary.release_pending_count },
              { label: 'In flight', value: model.summary.in_flight_count },
              {
                label: 'Failed / indeterminate',
                value: model.summary.failed_count + model.summary.indeterminate_count,
              },
            ]"
            :key="metric.label"
            class="min-w-24 bg-base-100/80 px-3 py-2"
          >
            <p class="hud-label">{{ metric.label }}</p>
            <p class="mt-1 font-mono text-lg font-semibold">{{ metric.value }}</p>
          </div>
        </div></template
      >
    </CadencePageHeading>
    <CadenceOpsListBodyFrame>
      <div class="flex flex-wrap items-center justify-between gap-3 text-xs text-base-content/75">
        <p>
          Snapshot observed
          <time id="command-monitor-observed" :datetime="model.observed_at">{{
            model.observed_at
          }}</time
          >. Refresh to read current state.
        </p>
        <button
          id="command-monitor-refresh"
          type="button"
          class="btn btn-ghost btn-sm"
          :disabled="pending"
          @click="retry"
        >
          Refresh
        </button>
      </div>
      <section
        v-if="model.focus.status !== 'not_selected'"
        id="command-monitor-focus"
        class="border-l-2 border-info bg-info/10 p-3"
        :data-followed-command="model.query.focus_command_id"
      >
        <div class="flex items-start justify-between gap-3">
          <div>
            <p class="hud-label">Focused command</p>
            <p class="mt-1 break-all font-mono">{{ model.query.focus_command_id }}</p>
          </div>
          <button
            id="command-monitor-clear-focus"
            class="btn btn-ghost btn-xs"
            type="button"
            :disabled="pending"
            @click="clearFocus"
          >
            Clear focus
          </button>
        </div>
        <div v-if="model.focus.status === 'ready'" class="mt-3">
          <p class="mb-3 font-semibold">
            {{ model.focus.row.name }} · {{ label(model.focus.row.status) }}
          </p>
          <CommandEvidence :row="model.focus.row" />
          <a
            v-if="historyHref(model.focus.row.id)"
            id="command-focus-history"
            :href="historyHref(model.focus.row.id)"
            class="btn btn-ghost btn-sm"
            @click="openHistory($event, model.focus.row.id)"
            >Open full command history</a
          >
          <a
            class="btn btn-ghost btn-sm mt-3"
            v-if="reviewHref(model.focus.row.id)"
            :href="reviewHref(model.focus.row.id)"
            data-command-review-focus
            @click="reviewRequest($event, model.focus.row.id)"
            >Review request</a
          >
        </div>
        <p v-else role="status" class="mt-3 text-sm">
          This command is not available in the current mission projection.
        </p>
      </section>
      <form
        id="command-monitor-filters"
        class="grid gap-3 border border-base-300 bg-base-200/25 p-3 md:grid-cols-3"
        @submit.prevent="
          navigate({
            ...model.query,
            status: fields.status,
            target: fields.target,
            query: fields.query,
            page: '1',
          })
        "
      >
        <label class="block"
          ><span class="hud-label mb-1.5 block">State</span
          ><select
            id="command-monitor-status"
            v-model="fields.status"
            class="select w-full"
            :disabled="pending"
          >
            <option value="all">All states</option>
            <option v-for="state in commandStates" :key="state" :value="state">
              {{ label(state) }}
            </option>
          </select></label
        >
        <label class="block"
          ><span class="hud-label mb-1.5 block">Target endpoint</span
          ><input
            id="command-monitor-target"
            v-model="fields.target"
            list="command-monitor-targets"
            class="input w-full"
            maxlength="256"
            :disabled="pending" /><datalist id="command-monitor-targets">
            <option value="all">All targets</option>
            <option v-for="target in model.targets" :key="target" :value="target" /></datalist
        ></label>
        <label class="block"
          ><span class="hud-label mb-1.5 block">Command or requester</span
          ><input
            id="command-monitor-query"
            v-model="fields.query"
            type="search"
            class="input w-full"
            maxlength="256"
            :disabled="pending"
        /></label>
        <div class="flex gap-2 md:col-span-3">
          <button
            id="command-monitor-apply"
            type="submit"
            class="btn btn-primary btn-sm"
            :disabled="pending"
          >
            Apply filters</button
          ><button
            id="command-monitor-reset"
            type="button"
            class="btn btn-ghost btn-sm"
            :disabled="pending"
            @click="
              navigate({ ...model.query, status: 'all', target: 'all', query: '', page: '1' })
            "
          >
            Reset filters
          </button>
        </div>
        <p
          v-if="filterError"
          id="command-monitor-filter-error"
          role="alert"
          class="text-xs text-error md:col-span-3"
        >
          Filters must contain no control characters and be at most 256 UTF-8 bytes each. Shorten
          the target or search text and try again.
        </p>
        <p v-if="model.targets_limited" class="text-xs text-warning md:col-span-3">
          Target suggestions are limited to 200 entries. Enter an exact endpoint ID to search
          another target.
        </p>
      </form>
      <p class="font-mono text-xs text-base-content/75">
        {{ model.total }} matching commands · {{ model.summary.total_count }} in the mission
        projection
      </p>
      <CadenceOpsListFrame>
        <div id="command-monitor-rows">
          <div
            v-if="model.status === 'empty'"
            id="command-monitor-empty"
            role="status"
            class="px-6 py-12 text-center"
          >
            <h2 class="font-semibold">No matching commands</h2>
            <p class="mt-2 text-sm text-base-content/75">
              The projection is available; no requests match these filters.
            </p>
          </div>
          <article
            v-for="row in model.rows"
            :id="`command-request-${encodeURIComponent(row.id)}`"
            :key="row.id"
            :data-command-request="row.id"
            :data-command-state="row.status"
            class="grid gap-3 border-b border-base-300/60 px-4 py-3 last:border-b-0 xl:grid-cols-[9rem_minmax(0,1fr)_13rem_10rem_auto_auto] xl:items-center"
          >
            <span
              class="font-mono text-xs uppercase"
              :class="
                ['failed', 'indeterminate'].includes(row.status)
                  ? 'text-error'
                  : row.status === 'release_pending'
                    ? 'text-warning'
                    : 'text-info'
              "
              >{{ label(row.status) }}</span
            >
            <div class="min-w-0">
              <p class="truncate font-semibold">{{ row.name }}</p>
              <p class="break-all font-mono text-xs text-base-content/75">{{ row.id }}</p>
              <p v-if="row.command_id" class="break-all font-mono text-xs text-base-content/75">
                {{ row.command_id }}
              </p>
            </div>
            <div>
              <p class="hud-label">Target</p>
              <p class="mt-1 break-all font-mono text-xs">{{ row.target ?? "Not recorded" }}</p>
            </div>
            <div>
              <p class="hud-label">Requested by</p>
              <p class="mt-1 break-all text-xs">{{ row.requested_by }}</p>
            </div>
            <a
              class="btn btn-ghost btn-xs"
              :href="href({ ...model.query, focus_command_id: row.id })"
              :aria-disabled="pending"
              :data-command-follow="row.id"
              @click="follow($event, row.id)"
              >{{ model.query.focus_command_id === row.id ? "Focused" : "Focus" }}</a
            >
            <a
              class="btn btn-ghost btn-xs"
              v-if="reviewHref(row.id)"
              :href="reviewHref(row.id)"
              :data-command-review="row.id"
              @click="reviewRequest($event, row.id)"
              >Review request</a
            >
            <CadenceDetailsFrame class="border-t border-base-300/50 pt-2 xl:col-span-6"
              ><summary class="cursor-pointer font-mono text-xs uppercase text-base-content/75">
                Queue, release, and verifier evidence
              </summary>
              <div class="mt-3">
                <CommandEvidence :row="row" /><a
                  v-if="historyHref(row.id)"
                  :data-command-history="row.id"
                  :href="historyHref(row.id)"
                  class="btn btn-ghost btn-sm"
                  @click="openHistory($event, row.id)"
                  >Open full command history</a
                >
              </div></CadenceDetailsFrame
            >
          </article>
        </div>
      </CadenceOpsListFrame>
      <nav aria-label="Command pages" class="flex items-center justify-between gap-3">
        <button
          id="command-monitor-previous"
          type="button"
          class="btn btn-ghost btn-sm"
          :disabled="pending || currentPage <= 1"
          @click="navigate({ ...model.query, page: String(currentPage - 1) })"
        >
          Previous</button
        ><span class="font-mono text-xs">Page {{ currentPage }} of {{ model.pages }}</span
        ><button
          id="command-monitor-next"
          type="button"
          class="btn btn-ghost btn-sm"
          :disabled="pending || currentPage >= model.pages"
          @click="navigate({ ...model.query, page: String(currentPage + 1) })"
        >
          Next
        </button>
      </nav>
    </CadenceOpsListBodyFrame>
  </CadenceOpsViewport>
</template>
