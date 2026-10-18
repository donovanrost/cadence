<script setup lang="ts">
import { computed, ref } from "vue";
import { useOpsHeaders } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";
import CadenceField from "@cadence/ui/CadenceField.vue";
import type { OpsPagePort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import { same, type HistoryPage, type HistoryInputs } from "./native-contract";
import { useHistoricalWorkflows } from "./native-state";
defineOptions({ inheritAttrs: false });
const props = defineProps<{ page: HistoryPage; port: OpsPagePort; readPort: OpsPageReadPort }>();
const state = useHistoricalWorkflows(() => props.page, props.port, props.readPort);
const {
  page: currentPage,
  draft,
  reasons,
  selectedBinding,
  lastEffect,
  pending,
  locked,
  disabled,
  notice,
} = state;
const receipt = computed(() =>
  lastEffect.value?.status === "completed" ? lastEffect.value.result : null,
);
const retryCounts = computed(() =>
  lastEffect.value?.status === "completed" && lastEffect.value.action === "retry-group"
    ? lastEffect.value.result.retry_counts
    : null,
);
const model = computed(() => currentPage.value.model),
  selected = computed(() => model.value.selected);
const search = ref(model.value.query.binding_q),
  correctionEvent = ref("");
const missionPath = `/missions/${encodeURIComponent(props.page.model.context.mission_id)}/ops/data-operations`;
const route = computed(() => missionPath + (model.value.mode === "manage" ? "/manage" : ""));
const groupHref = (id: string) => `${route.value}?group=${encodeURIComponent(id)}`;
const bindingOptions = computed(() => {
  const rows = [...model.value.bindings.entries];
  if (selectedBinding.value && !rows.some((b) => b.id === selectedBinding.value?.id))
    rows.unshift(selectedBinding.value);
  return rows;
});
const repeatedRequest = computed(
  () =>
    lastEffect.value?.action === "record-request" &&
    lastEffect.value.status === "completed" &&
    same(lastEffect.value.input.request, draft),
);
const currentBinding = computed(() =>
  model.value.bindings.entries.find((b) => b.id === selectedBinding.value?.id),
);
const bindingChangedSinceReview = computed(
  () =>
    currentBinding.value &&
    selectedBinding.value &&
    currentBinding.value.evidence !== selectedBinding.value.evidence,
);
const stageLabels: Record<string, string> = {
  approved: "Approve",
  rejected: "Reject",
  started: "Start",
  completed: "Complete",
  failed: "Mark failed",
};
const requestDisabled = computed(
  () =>
    disabled.value ||
    !selectedBinding.value ||
    bindingChangedSinceReview.value ||
    repeatedRequest.value ||
    new TextEncoder().encode(draft.reason).length > 4096,
);
const metrics = [
  ["requested", "Requested"],
  ["approved", "Approved"],
  ["started", "Started"],
  ["completed", "Completed"],
  ["failed", "Failed"],
] as const;
const detailPages = computed(() =>
  selected.value
    ? ([
        ["audit_page", "Audit", selected.value.audit],
        ["jobs_page", "Jobs", selected.value.jobs],
        ["origins_page", "Origins", selected.value.origins],
      ] as const)
    : [],
);
function bindingChanged(event: Event) {
  if (!(event.currentTarget instanceof HTMLSelectElement)) return;
  const value = event.currentTarget.value;
  const b = model.value.bindings.entries.find((x) => x.id === value);
  if (b) state.selectBinding(b);
}
function request(action: "validate-request" | "record-request") {
  if (requestDisabled.value) return;
  return state.execute(action, {
    request: { ...draft },
    binding_evidence: selectedBinding.value?.evidence ?? "",
  });
}
async function decide(
  ...[action, extra, reason]:
    | ["transition-group", Pick<HistoryInputs["transition-group"], "stage">, string]
    | ["retry-group", Record<never, never>, string]
    | ["request-correction", Pick<HistoryInputs["request-correction"], "event_id">, string]
) {
  const group = selected.value;
  if (!group || disabled.value || !reason.trim() || new TextEncoder().encode(reason).length > 4096)
    return;
  if (!window.confirm(`Apply this decision to request group ${group.id}?`)) return;
  const decision = {
    group_id: group.id,
    evidence: group.evidence,
    reason,
    confirmed: true as const,
  };
  if (action === "transition-group")
    await state.execute(action, { ...decision, stage: extra.stage });
  else if (action === "request-correction")
    await state.execute(action, { ...decision, event_id: extra.event_id });
  else await state.execute(action, decision);
}
function utc(event: Event, key: "source_from" | "source_to") {
  if (!(event.currentTarget instanceof HTMLInputElement)) return;
  const value = event.currentTarget.value;
  draft[key] = value ? value + "Z" : "";
}
function confirmRequest(event: Event) {
  if (event.currentTarget instanceof HTMLInputElement)
    draft.confirmed = event.currentTarget.checked ? "true" : "false";
}
const history = "/missions/:mission_id/ops/data-operations";
const historyDescription =
  "Request historical telemetry, follow each item and review the evidence behind recovery decisions.";
const historyRefresh = () => ({ run: () => state.refresh(), pending: pending.value });
const historyParams = () => ({ mission_id: model.value.context.mission_id });
useOpsHeaders({
  [history]: () => ({
    description: historyDescription,
    actions: model.value.permissions.manage
      ? [
          {
            id: "manage",
            label: "Manage workflows",
            icon: "hero-wrench-screwdriver",
            href: href("/missions/:mission_id/ops/data-operations/manage", historyParams()),
          },
        ]
      : [],
    refresh: historyRefresh(),
  }),
  "/missions/:mission_id/ops/data-operations/manage": () => ({
    description: historyDescription,
    actions: [
      {
        id: "reader",
        label: "Reader view",
        icon: "hero-eye",
        href: href(history, historyParams()),
      },
    ],
    refresh: historyRefresh(),
  }),
});
</script>
<template>
  <main id="ops-data-operations-page" class="min-w-0 space-y-5">
    <p v-if="notice" id="history-notice" role="status" class="border border-base-300 p-3 text-sm">
      {{ notice }}
    </p>
    <p
      v-if="locked"
      id="history-unconfirmed"
      role="alert"
      class="border border-warning p-3 text-sm"
    >
      The last outcome is unconfirmed. Refresh to recover the response, or inspect its audit in
      another tab before taking further action.
    </p>
    <section
      v-if="lastEffect"
      id="history-operation"
      class="space-y-2 border border-base-300 bg-base-100 p-4 text-sm"
      aria-label="Last workflow operation"
    >
      <p>
        <strong>{{
          lastEffect.status === "completed"
            ? "Operation recorded"
            : lastEffect.status === "rejected"
              ? "Operation not accepted"
              : "Outcome unconfirmed"
        }}</strong>
      </p>
      <p class="break-all font-mono text-xs">Operation {{ lastEffect.id }}</p>
      <template v-if="lastEffect.result?.group_id">
        <a :href="groupHref(lastEffect.result.group_id)" target="_blank" rel="noopener" class="link"
          >Inspect group {{ lastEffect.result.group_id }}</a
        >
        <p v-if="receipt">
          {{ receipt.event_count }} audit event(s), {{ receipt.job_count }} job(s) returned.
        </p>
        <ul
          v-if="receipt?.event_ids.length"
          aria-label="Recorded event identities"
          class="space-y-1 font-mono text-xs"
        >
          <li v-for="id in receipt.event_ids" :key="id" class="break-all">{{ id }}</li>
        </ul>
        <ul
          v-if="receipt?.job_ids.length"
          aria-label="Returned job identities"
          class="space-y-1 font-mono text-xs"
        >
          <li v-for="id in receipt.job_ids" :key="id" class="break-all">{{ id }}</li>
        </ul>
        <p v-if="receipt && (receipt.event_ids_truncated || receipt.job_ids_truncated)">
          Showing the first 25 identities. Use the group audit and job pages to inspect the full
          result.
        </p>
        <p v-if="retryCounts">
          Retries: {{ retryCounts.retried }}; skipped: {{ retryCounts.skipped }}; nonretryable:
          {{ retryCounts.nonretryable }}; errors: {{ retryCounts.failed }}.
        </p>
      </template>
    </section>
    <div class="grid min-w-0 gap-5 xl:grid-cols-[18rem_minmax(0,1fr)]">
      <aside id="data-operation-groups" class="min-w-0 border border-base-300 bg-base-100">
        <div class="border-b border-base-300 p-3">
          <h2 class="text-sm font-semibold">Request groups</h2>
          <p class="text-xs text-base-content/60">
            {{ model.groups.total }} groups · page {{ model.groups.page }}
          </p>
        </div>
        <p v-if="!model.groups.entries.length" class="p-4 text-sm text-base-content/60">
          No request groups on this page.
        </p>
        <button
          v-for="group in model.groups.entries"
          :id="'history-group-' + group.id"
          :key="group.id"
          type="button"
          class="block w-full space-y-2 border-b border-base-300 p-3 text-left hover:bg-primary/5"
          :class="{ 'bg-primary/10': selected?.id === group.id }"
          :disabled="pending || locked"
          :aria-pressed="selected?.id === group.id"
          @click="
            state.chooseQuery({
              group: group.id,
              audit_page: '1',
              jobs_page: '1',
              origins_page: '1',
            })
          "
        >
          <span class="block break-all font-mono text-xs font-semibold">{{ group.id }}</span
          ><span class="block text-xs"
            >{{ group.workflow }} · {{ group.summary?.state ?? "Unavailable" }}</span
          ><span class="block text-xs text-base-content/60"
            >{{ group.summary?.progress }} · {{ group.event_count }} events</span
          >
        </button>
        <nav aria-label="Request group pages" class="flex gap-2 p-3">
          <button
            id="history-groups-previous"
            type="button"
            class="btn btn-xs btn-outline"
            :disabled="pending || locked || model.groups.page <= 1"
            @click="state.chooseQuery({ page: String(model.groups.page - 1) })"
          >
            Previous</button
          ><button
            id="history-groups-next"
            type="button"
            class="btn btn-xs btn-outline"
            :disabled="pending || locked || model.groups.page * 25 >= model.groups.total"
            @click="state.chooseQuery({ page: String(model.groups.page + 1) })"
          >
            Next
          </button>
        </nav>
      </aside>
      <section
        id="data-operation-detail"
        class="min-w-0 space-y-5 border border-base-300 bg-base-100 p-5"
      >
        <template v-if="selected">
          <header>
            <p class="hud-label">{{ selected.workflow }} request group</p>
            <h2 id="data-operation-group-id" class="mt-2 break-all font-mono text-sm font-semibold">
              {{ selected.id }}
            </h2>
            <p class="mt-2 text-sm">
              {{ selected.summary.state }} · {{ selected.summary.progress }}
            </p>
            <a :href="groupHref(selected.id)" target="_blank" rel="noopener" class="link text-xs"
              >Open this group in another tab</a
            >
          </header>
          <dl class="grid grid-cols-2 gap-3 sm:grid-cols-5">
            <div v-for="[key, label] in metrics" :key="key" class="border border-base-300 p-3">
              <dt class="hud-label">{{ label }}</dt>
              <dd class="mt-1 font-mono text-lg">{{ selected.summary[key] }}</dd>
            </div>
          </dl>
          <section
            v-if="model.mode === 'manage' && model.permissions.manage"
            id="history-decisions"
            class="space-y-4 border-y border-base-300 py-4"
            aria-label="Recovery decisions"
          >
            <h3 class="text-sm font-semibold">Review a group decision</h3>
            <CadenceField label="Transition reason" control-id="history-transition-reason">
              <textarea
                id="history-transition-reason"
                v-model="reasons.transition"
                class="textarea textarea-bordered w-full"
                maxlength="4096"
              />
            </CadenceField>
            <div class="flex flex-wrap gap-2">
              <button
                v-for="transition in selected.transitions"
                :id="'history-' + transition.stage"
                :key="transition.stage"
                type="button"
                class="btn btn-sm btn-outline"
                :disabled="disabled || !reasons.transition.trim() || !transition.eligible_count"
                @click="decide('transition-group', { stage: transition.stage }, reasons.transition)"
              >
                {{ stageLabels[transition.stage] }} · {{ transition.eligible_count }} eligible
              </button>
            </div>
            <CadenceField label="Retry reason" control-id="history-retry-reason">
              <textarea
                id="history-retry-reason"
                v-model="reasons.retry"
                class="textarea textarea-bordered w-full"
                maxlength="4096"
              />
            </CadenceField>
            <button
              id="history-retry-group"
              type="button"
              class="btn btn-sm btn-outline"
              :disabled="disabled || !reasons.retry.trim() || !selected.retry.eligible_count"
              @click="decide('retry-group', {}, reasons.retry)"
            >
              Retry {{ selected.retry.eligible_count }} failed item(s)
            </button>
            <CadenceField label="Failed event to correct" control-id="history-correction-event"
              ><select
                id="history-correction-event"
                v-model="correctionEvent"
                class="select select-bordered w-full"
              >
                <option value="">Select an eligible event from this audit page</option>
                <option
                  v-for="event in selected.audit.entries.filter((e) => e.correction_available)"
                  :key="event.id"
                  :value="event.id"
                >
                  {{ event.id }} · {{ event.point_id ?? event.run_id }}
                </option>
              </select></CadenceField
            >
            <CadenceField label="Correction reason" control-id="history-correction-reason">
              <textarea
                id="history-correction-reason"
                v-model="reasons.correction"
                class="textarea textarea-bordered w-full"
                maxlength="4096"
              />
            </CadenceField>
            <button
              id="history-request-correction"
              type="button"
              class="btn btn-sm btn-outline"
              :disabled="
                disabled ||
                !reasons.correction.trim() ||
                !selected.audit.entries.some(
                  (e) => e.id === correctionEvent && e.correction_available,
                )
              "
              @click="
                decide('request-correction', { event_id: correctionEvent }, reasons.correction)
              "
            >
              Request correction
            </button>
          </section>
          <section aria-labelledby="history-audit-title">
            <h3 id="history-audit-title" class="mb-3 text-sm font-semibold">
              Audit · {{ selected.audit.total }} events
            </h3>
            <ol id="history-audit" class="space-y-3">
              <li
                v-for="event in selected.audit.entries"
                :id="'history-event-' + event.id"
                :key="event.id"
                class="space-y-1 border border-base-300 p-3 text-xs"
              >
                <p class="break-all font-mono">{{ event.id }}</p>
                <p>{{ event.stage }} · {{ event.occurred_at }}</p>
                <p class="break-all">
                  Run {{ event.run_id }} · {{ event.point_id ?? "All dataset points" }}
                </p>
                <p class="break-all">
                  {{ event.realm }} · source {{ event.source_id }} · binding {{ event.binding_id }}
                </p>
                <p v-if="event.source_from || event.source_to">
                  {{ event.source_from }} → {{ event.source_to }}
                </p>
                <details v-if="event.reason.length > 240">
                  <summary class="cursor-pointer">View decision reason</summary>
                  <p class="mt-2 whitespace-pre-wrap break-words">{{ event.reason }}</p>
                </details>
                <p v-else class="whitespace-pre-wrap break-words">{{ event.reason }}</p>
                <p v-if="event.reason_truncated">Reason display truncated.</p>
                <p v-if="event.operation_id" class="break-all font-mono text-base-content/60">
                  Operation {{ event.operation_id }}
                </p>
              </li>
            </ol>
          </section>
          <section aria-labelledby="history-jobs-title">
            <h3 id="history-jobs-title" class="mb-3 text-sm font-semibold">
              Jobs · {{ selected.jobs.total }}
            </h3>
            <ul class="space-y-2">
              <li
                v-for="job in selected.jobs.entries"
                :key="job.id"
                class="break-all border border-base-300 p-3 font-mono text-xs"
              >
                {{ job.id }} · {{ job.status }} · attempt {{ job.attempts }}<br />Run
                {{ job.run_id }}
              </li>
            </ul>
            <p v-if="!selected.jobs.entries.length" class="text-xs text-base-content/60">
              No jobs on this page.
            </p>
          </section>
          <section v-if="selected.origins.total" aria-labelledby="history-origins-title">
            <h3 id="history-origins-title" class="text-sm font-semibold">
              Origins · {{ selected.origins.total }}
            </h3>
            <ul class="space-y-1">
              <li
                v-for="origin in selected.origins.entries"
                :key="origin.kind + origin.id"
                class="break-all font-mono text-xs"
              >
                {{ origin.kind }} · {{ origin.id }}
              </li>
            </ul>
          </section>
          <div class="flex flex-wrap gap-4">
            <nav
              v-for="[key, label, pager] in detailPages"
              :key="key"
              :aria-label="label + ' pages'"
              class="space-y-2"
            >
              <p class="text-xs">{{ label }} · page {{ pager.page }}</p>
              <div class="flex gap-2">
                <button
                  :id="'history-' + key + '-previous'"
                  type="button"
                  class="btn btn-xs btn-outline"
                  :disabled="pending || locked || pager.page <= 1"
                  @click="state.chooseQuery({ [key]: String(pager.page - 1) })"
                >
                  Previous</button
                ><button
                  :id="'history-' + key + '-next'"
                  type="button"
                  class="btn btn-xs btn-outline"
                  :disabled="pending || locked || pager.page * 25 >= pager.total"
                  @click="state.chooseQuery({ [key]: String(pager.page + 1) })"
                >
                  Next
                </button>
              </div>
            </nav>
          </div>
        </template>
        <p v-else class="py-12 text-center text-sm text-base-content/60">
          Select a request group to inspect its progress, jobs and audit evidence.
        </p>
      </section>
    </div>
    <section id="history-request" class="border border-base-300 bg-base-100 p-5">
      <h2 class="text-sm font-semibold">Request historical telemetry</h2>
      <p class="mt-1 text-xs text-base-content/60">
        Choose an active telemetry binding and a UTC source interval. Blank point IDs request the
        complete dataset.
      </p>
      <form
        id="history-binding-search"
        class="mt-4 flex flex-wrap items-end gap-2"
        @submit.prevent="state.chooseQuery({ binding_q: search, bindings_page: '1' })"
      >
        <CadenceField label="Find a binding" control-id="history-binding-query"
          ><input
            id="history-binding-query"
            v-model="search"
            type="search"
            class="input input-bordered w-full"
            maxlength="200" /></CadenceField
        ><button type="submit" class="btn btn-sm btn-outline" :disabled="pending || locked">
          Search bindings
        </button>
      </form>
      <form
        id="historical-workflow-form"
        class="mt-4 space-y-3"
        @submit.prevent="request('record-request')"
      >
        <div class="grid gap-4 md:grid-cols-2">
          <CadenceField label="Workflow" control-id="history-workflow"
            ><select
              id="history-workflow"
              v-model="draft.workflow"
              class="select select-bordered w-full"
            >
              <option value="backfill">Backfill</option>
              <option value="import">Import</option>
            </select></CadenceField
          >
          <CadenceField label="Request group ID (optional)" control-id="history-run"
            ><input
              id="history-run"
              v-model="draft.run_id"
              class="input input-bordered w-full font-mono"
              maxlength="232"
              placeholder="Generated when blank"
          /></CadenceField>
          <CadenceField label="Telemetry binding" control-id="history-binding"
            ><select
              id="history-binding"
              :value="draft.source_binding_id"
              class="select select-bordered w-full"
              required
              @change="bindingChanged"
            >
              <option value="">Select a binding</option>
              <option v-for="binding in bindingOptions" :key="binding.id" :value="binding.id">
                {{ binding.id }} · {{ binding.realm }} · v{{ binding.version }}
              </option>
            </select></CadenceField
          >
          <p class="self-center break-all text-xs text-base-content/60">
            {{
              draft.data_source_id
                ? "Source " + draft.data_source_id + " · " + draft.realm
                : "Select a binding to capture its source and realm."
            }}
          </p>
          <div v-if="bindingChangedSinceReview && currentBinding" class="space-y-2 text-sm">
            <p>
              The selected binding has changed. Review its current source and version before
              submitting.
            </p>
            <button
              id="history-use-current-binding"
              type="button"
              class="btn btn-sm btn-outline"
              :disabled="disabled"
              @click="currentBinding && state.selectBinding(currentBinding)"
            >
              Use version {{ currentBinding.version }} · {{ currentBinding.source_id }}
            </button>
          </div>
          <CadenceField label="Source start (UTC)" control-id="history-source-from"
            ><input
              id="history-source-from"
              :value="draft.source_from.replace(/Z$/, '')"
              type="datetime-local"
              step="1"
              required
              class="input input-bordered w-full"
              @input="utc($event, 'source_from')"
          /></CadenceField>
          <CadenceField label="Source end (UTC)" control-id="history-source-to"
            ><input
              id="history-source-to"
              :value="draft.source_to.replace(/Z$/, '')"
              type="datetime-local"
              step="1"
              required
              class="input input-bordered w-full"
              @input="utc($event, 'source_to')"
          /></CadenceField>
        </div>
        <nav aria-label="Binding pages" class="flex flex-wrap items-center gap-2">
          <span class="text-xs"
            >{{ model.bindings.total }} bindings · page {{ model.bindings.page }}</span
          ><button
            id="history-bindings-previous"
            type="button"
            class="btn btn-xs btn-outline"
            :disabled="pending || locked || model.bindings.page <= 1"
            @click="state.chooseQuery({ bindings_page: String(model.bindings.page - 1) })"
          >
            Previous</button
          ><button
            id="history-bindings-next"
            type="button"
            class="btn btn-xs btn-outline"
            :disabled="pending || locked || model.bindings.page * 25 >= model.bindings.total"
            @click="state.chooseQuery({ bindings_page: String(model.bindings.page + 1) })"
          >
            Next
          </button>
        </nav>
        <CadenceField
          label="Point IDs (optional; comma or newline separated)"
          control-id="history-points"
        >
          <textarea
            id="history-points"
            v-model="draft.point_ids"
            class="textarea textarea-bordered w-full font-mono"
            maxlength="8192"
          />
        </CadenceField>
        <CadenceField label="Request reason" control-id="history-reason">
          <textarea
            id="history-reason"
            v-model="draft.reason"
            class="textarea textarea-bordered w-full"
            maxlength="4096"
          />
        </CadenceField>
        <label class="flex items-center gap-2 text-sm"
          ><input
            id="history-confirmed"
            type="checkbox"
            class="checkbox checkbox-sm"
            :checked="draft.confirmed === 'true'"
            @change="confirmRequest($event)"
          />I confirm this historical telemetry request.</label
        >
        <div class="flex flex-wrap gap-2">
          <button
            id="history-validate-request"
            type="button"
            class="btn btn-sm btn-outline"
            :disabled="requestDisabled"
            @click="request('validate-request')"
          >
            Validate request</button
          ><button
            id="history-record-request"
            type="submit"
            class="btn btn-sm btn-primary"
            :disabled="requestDisabled || draft.confirmed !== 'true'"
          >
            Request workflow
          </button>
        </div>
        <p v-if="repeatedRequest" class="text-xs text-base-content/60">
          This request was recorded. Change the request values to prepare a new operation.
        </p>
      </form>
    </section>
  </main>
</template>
