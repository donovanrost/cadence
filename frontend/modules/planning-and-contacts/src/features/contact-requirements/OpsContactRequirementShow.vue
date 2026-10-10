<script setup lang="ts">
import { computed, onMounted, onBeforeUnmount, ref, watch } from "vue";
import type {
  OpsContactRequirementShowProps,
  OpsContactRequirementShowEmits,
  Opportunity,
} from "./OpsContactRequirementShow.contracts";
import {
  admitRequirementDetail,
  canPlan,
  canCreate,
  decision,
  reviewHref,
} from "./requirement-detail";
import {
  completedSelection,
  persistSelection,
  restoreSelection,
  selectionIdentity,
  selectionStorageKey,
  SELECTION_LIMIT,
} from "./requirement-selection";
import RequirementDetailPagination from "./RequirementDetailPagination.vue";
import { headerText, useOpsHeader } from "@cadence/plugin-sdk/page-header";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";
import CadencePanel from "@cadence/ui/CadencePanel.vue";

const props = defineProps<OpsContactRequirementShowProps>();
const emit = defineEmits<OpsContactRequirementShowEmits>();
const d = computed(() => admitRequirementDetail(props.detail));
const selected = ref<string[]>([]);
const notice = ref("");
const localPending = ref(false);
const pending = computed(() => props.workflow?.pending ?? localPending.value);
const persistent = ref(false);
let storage: Storage | undefined;
let releaseNavigationGuard: (() => void) | undefined;

function restore() {
  selected.value = [];
  if (!storage || !d.value) return;
  try {
    const restored = restoreSelection(storage, d.value);
    selected.value = restored.ids;
    if (restored.changed)
      notice.value =
        "The review identity changed or saved selection was invalid. Selection cleared.";
    if (!canCreate(d.value) && selected.value.length) clear();
  } catch {
    persistent.value = false;
    notice.value = "Tab storage is unavailable. Clear selections before changing pages.";
  }
}
function save() {
  if (!storage || !d.value) return;
  try {
    persistSelection(storage, d.value, selected.value);
  } catch {
    persistent.value = false;
    notice.value = "Selection could not be saved. Clear it before changing pages.";
  }
}
function clear() {
  selected.value = [];
  save();
}
function toggle(o: Opportunity) {
  if (!d.value || !canCreate(d.value) || !o.eligible || pending.value) return;
  if (selected.value.includes(o.id)) selected.value = selected.value.filter((id) => id !== o.id);
  else if (selected.value.length < SELECTION_LIMIT) selected.value = [...selected.value, o.id];
  else {
    notice.value = "Select at most " + SELECTION_LIMIT + " opportunities.";
    return;
  }
  save();
}
function canLeave() {
  const busy = props.workflow?.busy ?? pending.value;
  if (busy || (!persistent.value && selected.value.length)) {
    notice.value = busy
      ? "Wait for the current operation to finish."
      : "Clear the unsaved selection before changing pages.";
    return false;
  }
  return true;
}
function navigate(event: MouseEvent) {
  if (!canLeave()) event.preventDefault();
}
function plan() {
  if (!d.value || !canPlan(d.value) || pending.value) return;
  if (!props.workflow) localPending.value = true;
  emit("plan", decision(d.value));
}
function createPlan() {
  if (
    !d.value ||
    !canCreate(d.value) ||
    !d.value.selected_run ||
    !selected.value.length ||
    pending.value
  )
    return;
  if (!props.workflow) localPending.value = true;
  emit("create-plan", {
    ...decision(d.value),
    planning_run_id: d.value.selected_run.id,
    selected_snapshot_ids: [...selected.value],
  });
}
function acceptResult(result: unknown) {
  if (d.value && completedSelection(d.value, result)) clear();
}
function completed(event: Event) {
  if (!props.workflow && event instanceof CustomEvent) acceptResult(event.detail);
}
watch(() => props.workflow?.result, acceptResult);
watch(
  () => (d.value ? selectionIdentity(d.value) + ":" + canCreate(d.value) : null),
  () => {
    localPending.value = false;
    restore();
  },
);
onMounted(() => {
  try {
    storage = window.sessionStorage;
    storage.getItem(selectionStorageKey);
    persistent.value = true;
  } catch {
    notice.value = "Tab storage is unavailable. Clear selections before changing pages.";
  }
  restore();
  releaseNavigationGuard = props.workflow?.guardNavigation?.(canLeave);
  if (props.workflow) acceptResult(props.workflow.result);
  else window.addEventListener("cadence:ops-action-result", completed);
});
onBeforeUnmount(() => {
  releaseNavigationGuard?.();
  window.removeEventListener("cadence:ops-action-result", completed);
});
const label = (value: string) => value.replaceAll("_", " ").replace(/^./, (c) => c.toUpperCase());
const rowId = (kind: string, id: string) => kind + "-" + encodeURIComponent(id);
useOpsHeader("/missions/:mission_id/ops/requirements/:contact_requirement_id", () => {
  const detail = d.value;
  if (!detail) return { title: "Contact requirement" };
  const requirement = detail.requirement;
  return {
    title: label(requirement.intent),
    description: headerText(requirement.outcome),
    facts: [
      `v${requirement.version} · ${requirement.priority} · ${requirement.direction}`,
      label(requirement.lifecycle_state),
    ],
    primary: {
      id: "plan-contact-requirement",
      label: "Search provider options",
      icon: "hero-magnifying-glass",
      disabled: !canPlan(detail) || pending.value,
      run: plan,
    },
  };
});
</script>

<template>
  <CadenceOpsViewport v-if="d" id="ops-contact-requirement-show-page">
    <aside
      v-if="!canPlan(d)"
      id="requirement-review-readonly"
      class="mb-5 border border-warning/40 bg-warning/5 p-4 text-sm"
    >
      This review is read-only. New searches and proposals require an active, current downlink
      requirement.
      <a
        v-if="d.requirement.version !== d.requirement.current_version"
        id="review-current-requirement"
        :href="reviewHref(d, d.requirement.current_version)"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="ml-2 text-primary underline"
        @click="navigate"
        >Review current version</a
      >
    </aside>
    <p
      v-if="notice"
      id="requirement-selection-notice"
      role="status"
      class="mb-4 border border-warning/30 p-3 text-sm"
    >
      {{ notice }}
    </p>

    <div class="grid gap-5 xl:grid-cols-[minmax(0,1.6fr)_minmax(18rem,0.8fr)]">
      <div class="min-w-0 space-y-5">
        <CadencePanel
          class="border border-base-300 bg-base-200/20"
          header-class="border-b border-base-300 p-4"
        >
          <template #header
            ><h2 class="hud-label">Provider search runs</h2>
            <p class="mt-1 text-sm text-base-content/55">
              Choose the exact search to review. Changing run or version clears selection.
            </p></template
          >
          <p
            v-if="!d.runs.entries.length"
            id="requirement-runs-empty"
            class="p-5 text-sm text-base-content/55"
          >
            No search runs on this page.
          </p>
          <a
            v-for="run in d.runs.entries"
            :id="rowId('review-run', run.id)"
            :key="run.id"
            :href="reviewHref(d, run.version, run.id)"
            data-phx-link="redirect"
            data-phx-link-state="push"
            :aria-current="run.id === d.selected_run?.id ? 'true' : undefined"
            :class="[
              'block border-b border-base-300 p-4 last:border-b-0',
              run.id === d.selected_run?.id && 'bg-primary/10',
            ]"
            @click="navigate"
          >
            <span class="flex flex-wrap justify-between gap-2 font-mono text-xs"
              ><span>v{{ run.version }} · {{ run.state }}</span
              ><time>{{ run.started_at }}</time></span
            >
            <span class="mt-1 block break-all font-mono text-xs text-base-content/55">{{
              run.id
            }}</span>
          </a>
          <RequirementDetailPagination :detail="d" section="runs" @navigate="navigate" />
        </CadencePanel>

        <CadencePanel
          class="border border-base-300 bg-base-200/20"
          header-class="border-b border-base-300 p-4"
        >
          <template #header
            ><h2 class="hud-label">Opportunity evidence</h2>
            <p id="requirement-selected-run" class="mt-2 break-all font-mono text-xs">
              {{
                d.selected_run
                  ? d.selected_run.id + " · " + d.selected_run.state
                  : "No run selected"
              }}
            </p>
            <p class="mt-2 text-sm text-base-content/55">
              Captured evidence, not a reservation or a live availability guarantee.
            </p></template
          >
          <p
            v-if="!d.opportunities.entries.length"
            id="requirement-opportunities-empty"
            class="p-5 text-sm text-base-content/55"
          >
            {{
              d.selected_run
                ? "No captured opportunities on this page."
                : "Select a search run above, or search for provider options."
            }}
          </p>
          <article
            v-for="o in d.opportunities.entries"
            :id="rowId('opportunity', o.id)"
            :key="o.id"
            :class="['border-b border-base-300 p-4', selected.includes(o.id) && 'bg-primary/5']"
          >
            <label class="flex items-start gap-3">
              <input
                :id="rowId('select', o.id)"
                type="checkbox"
                class="checkbox checkbox-sm mt-1 shrink-0"
                :checked="selected.includes(o.id)"
                :disabled="
                  !canCreate(d) ||
                  !o.eligible ||
                  pending ||
                  (!selected.includes(o.id) && selected.length >= SELECTION_LIMIT)
                "
                @change="toggle(o)"
              />
              <span class="min-w-0 flex-1"
                ><span class="block break-words font-semibold"
                  >{{ o.provider }} · {{ o.station }}</span
                ><span class="mt-1 block break-all font-mono text-xs text-base-content/60"
                  ><time class="block">{{ o.starts_at }}</time
                  ><time class="block">{{ o.ends_at }}</time></span
                ><span class="mt-2 block text-xs text-base-content/60"
                  >{{ o.eligible ? "Eligible when captured" : "Ineligible when captured" }} ·
                  {{ o.availability }}<span v-if="o.synthetic"> · Synthetic evidence</span></span
                ></span
              >
            </label>
            <p class="mt-2 break-all font-mono text-[0.65rem] text-base-content/45">
              Expires {{ o.expires_at }} · {{ o.id }}
            </p>
            <details class="mt-2 text-xs text-base-content/55">
              <summary>Evidence hash</summary>
              <code class="mt-1 block break-all">{{ o.content_sha256 }}</code>
            </details>
          </article>
          <RequirementDetailPagination :detail="d" section="opportunities" @navigate="navigate" />
          <div
            class="flex flex-wrap items-center justify-between gap-3 border-t border-base-300 p-4"
          >
            <span id="requirement-selected-count" class="font-mono text-sm text-primary"
              >{{ selected.length }} selected across pages</span
            >
            <div class="flex flex-wrap gap-2">
              <button
                id="clear-opportunity-selection"
                type="button"
                class="btn btn-ghost btn-sm"
                :disabled="!selected.length || pending"
                @click="clear"
              >
                Clear selection</button
              ><button
                id="create-contact-plan"
                type="button"
                class="btn btn-primary btn-sm"
                :disabled="!canCreate(d) || !selected.length || pending"
                @click="createPlan"
              >
                Create proposal
              </button>
            </div>
            <p class="w-full text-xs text-base-content/55">
              Up to {{ SELECTION_LIMIT }} opportunities. Creating a proposal does not reserve
              provider capacity.
            </p>
          </div>
        </CadencePanel>

        <CadencePanel
          class="border border-base-300 bg-base-200/20"
          header-class="border-b border-base-300 p-4"
        >
          <template #header><h2 class="hud-label">Route search outcomes</h2></template>
          <p
            v-if="!d.searches.entries.length"
            id="requirement-searches-empty"
            class="p-5 text-sm text-base-content/55"
          >
            No route search evidence on this page.
          </p>
          <article
            v-for="search in d.searches.entries"
            :id="rowId('search', search.id)"
            :key="search.id"
            class="border-b border-base-300 p-4"
          >
            <h3 class="break-words text-sm font-semibold">{{ search.provider }}</h3>
            <p class="mt-1 break-all font-mono text-xs text-base-content/55">
              {{ search.route_key }}
            </p>
            <p class="mt-2 text-sm">
              {{ label(search.outcome) }} · {{ search.opportunity_count }}
              {{ search.opportunity_count === 1 ? "opportunity" : "opportunities" }}
            </p>
            <details class="mt-2 text-xs text-base-content/55">
              <summary>Evidence hash</summary>
              <code class="mt-1 block break-all">{{ search.content_sha256 }}</code>
            </details>
          </article>
          <RequirementDetailPagination :detail="d" section="searches" @navigate="navigate" />
        </CadencePanel>
      </div>

      <aside class="min-w-0 space-y-5">
        <CadencePanel
          class="border border-base-300 bg-base-200/20"
          header-class="border-b border-base-300 p-4"
        >
          <template #header><h2 class="hud-label">Reviewed requirement</h2></template>
          <dl class="space-y-4 p-4 text-sm">
            <div>
              <dt class="hud-label">Acceptable window · UTC</dt>
              <dd class="mt-2 break-all font-mono text-xs">
                {{ d.requirement.earliest_start }}<br />{{ d.requirement.latest_end }}
              </dd>
            </div>
            <div>
              <dt class="hud-label">Rationale</dt>
              <dd class="mt-2 whitespace-pre-wrap break-words text-base-content/70">
                {{ d.requirement.rationale }}
              </dd>
            </div>
            <div>
              <dt class="hud-label">Immutable content hash</dt>
              <dd class="mt-2 break-all font-mono text-xs text-base-content/50">
                {{ d.requirement.content_sha256 }}
              </dd>
            </div>
          </dl>
        </CadencePanel>
        <CadencePanel
          class="border border-base-300 bg-base-200/20"
          header-class="border-b border-base-300 p-4"
        >
          <template #header
            ><h2 class="hud-label">Version history</h2>
            <p class="mt-1 text-xs text-base-content/55">
              Anchored at reviewed version {{ d.requirement.version }}.
            </p></template
          >
          <p v-if="!d.versions.entries.length" class="p-4 text-sm text-base-content/55">
            No versions on this page.
          </p>
          <a
            v-for="version in d.versions.entries"
            :id="rowId('review-version', version.id)"
            :key="version.id"
            :href="reviewHref(d, version.version)"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="block border-b border-base-300 p-4"
            @click="navigate"
            ><span class="font-mono text-xs text-primary">v{{ version.version }}</span
            ><time class="mt-1 block break-all font-mono text-xs text-base-content/55">{{
              version.created_at
            }}</time></a
          >
          <RequirementDetailPagination :detail="d" section="versions" @navigate="navigate" />
        </CadencePanel>
      </aside>
    </div>
  </CadenceOpsViewport>
  <section
    v-else
    id="requirement-detail-unavailable"
    role="alert"
    class="border border-warning/40 bg-warning/5 p-5"
  >
    <h2 class="text-lg font-semibold">Requirement review unavailable</h2>
    <p class="mt-2 text-sm">
      The review data is missing or incompatible. No planning action is available.
    </p>
  </section>
</template>
