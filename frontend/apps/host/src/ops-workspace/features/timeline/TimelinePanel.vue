<script setup lang="ts">
import { computed, nextTick, reactive, ref, watch } from "vue";
import { useOpsHeader } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";
import CadenceClipboardButton from "@cadence/ui/CadenceClipboardButton.vue";
import { filterKeys, referenceKeys, timelineHref, type TimelineModel } from "./contracts";
const props = defineProps<{
  model: TimelineModel;
  navigate: (href: string) => void;
  refresh: () => Promise<void>;
}>();
const draft = reactive({ ...props.model.query });
watch(
  () => props.model,
  (model) => Object.assign(draft, model.query),
);
const busy = ref(false);
const refreshError = ref(false);
const missionId = computed(() => props.model.context.mission_id);
const selected = computed(() => props.model.selected);
const details = ref<HTMLElement | null>(null);
watch(
  () => props.model.selected?.id,
  async (id, previous) => {
    if (id && id !== previous) {
      await nextTick();
      details.value?.focus();
    }
  },
);
const selectionHref = (id: string) =>
  timelineHref(missionId.value, { ...props.model.query, event_id: id });
const apply = () =>
  props.navigate(
    timelineHref(missionId.value, { ...draft, event_id: "", before_at: "", before_id: "" }),
  );
async function refreshPage() {
  if (busy.value) return;
  busy.value = true;
  refreshError.value = false;
  try {
    await props.refresh();
  } catch {
    refreshError.value = true;
  } finally {
    busy.value = false;
  }
}
const labels = {
  category: "Category",
  kind: "Event kind",
  severity: "Severity",
  spacecraft_id: "Spacecraft ID",
  from: "From (inclusive UTC)",
  to: "To (exclusive UTC)",
};
const referenceLabels = {
  spacecraft_id: "Spacecraft",
  source_endpoint_ref: "Source endpoint",
  scheduled_contact_id: "Scheduled contact",
  realized_contact_id: "Realized contact",
  path_id: "Path",
  capability_instance_id: "Capability instance",
  activation_id: "Activation",
  correlation_key: "Correlation",
};
const options = {
  category: ["operations", "health", "runtime", "transport"],
  severity: ["info", "warning", "error", "critical"],
};
useOpsHeader("/missions/:mission_id/ops/timeline", () => ({
  description: "Contacts, alarms, commands and runtime events across the mission.",
  actions: props.model.source_dashboard_id
    ? [
        {
          id: "source-dashboard",
          label: "Return to dashboard",
          icon: "hero-arrow-uturn-left",
          href: href("/missions/:mission_id/ops/dashboards/:dashboard_id", {
            mission_id: missionId.value,
            dashboard_id: props.model.source_dashboard_id,
          }),
        },
      ]
    : [],
  refresh: { run: refreshPage, pending: busy.value },
}));
</script>
<template>
  <div id="ops-timeline-page" class="space-y-5">
    <p v-if="refreshError" role="alert" class="text-sm text-warning">
      The refresh failed. These events are from the previous observation.
    </p>
    <form
      id="timeline-filter-form"
      class="grid gap-3 border border-base-300 bg-base-200/35 p-4 sm:grid-cols-2 xl:grid-cols-3"
      @submit.prevent="apply"
    >
      <div v-for="key in filterKeys" :key="key" class="min-w-0">
        <label :for="`timeline_${key}`" class="hud-label mb-2 block">{{ labels[key] }}</label>
        <select
          v-if="key === 'category' || key === 'severity'"
          :id="`timeline_${key}`"
          v-model="draft[key]"
          :name="key"
          class="select w-full"
          :aria-invalid="model.errors.includes(key)"
        >
          <option value="">All</option>
          <option v-if="draft[key] && !options[key].includes(draft[key])" :value="draft[key]">
            Invalid: {{ draft[key] }}
          </option>
          <option v-for="option in options[key]" :key="option" :value="option">{{ option }}</option>
        </select>
        <input
          v-else
          :id="`timeline_${key}`"
          v-model="draft[key]"
          :name="key"
          type="text"
          class="input w-full"
          maxlength="512"
          :placeholder="key === 'from' || key === 'to' ? 'YYYY-MM-DDTHH:mm:ssZ' : ''"
          :aria-invalid="model.errors.includes(key)"
        />
      </div>
      <div class="flex flex-wrap items-center gap-3 sm:col-span-2 xl:col-span-3">
        <button id="timeline-apply-filters" type="submit" class="btn btn-primary btn-sm">
          Apply filters
        </button>
        <a
          id="timeline-reset-filters"
          :href="timelineHref(missionId, { source_dashboard_id: model.query.source_dashboard_id })"
          class="btn btn-ghost btn-sm"
          >Reset</a
        >
        <p
          v-if="model.errors.length"
          id="timeline-filter-errors"
          role="alert"
          class="text-sm text-warning"
        >
          Review the filters: {{ model.errors.join(", ") }}.
        </p>
      </div>
    </form>
    <div class="flex flex-wrap justify-between gap-2 text-xs text-base-content/65">
      <p>Up to {{ model.limit }} events per page.</p>
      <p>
        Observed <time :datetime="model.observed_at">{{ model.observed_at }}</time>
      </p>
    </div>
    <nav aria-label="Timeline history" class="flex flex-wrap gap-3">
      <a
        v-if="model.query.before_at"
        id="timeline-newest-events"
        :href="
          timelineHref(missionId, { ...model.query, before_at: '', before_id: '', event_id: '' })
        "
        class="btn btn-ghost btn-sm"
        >Newest events</a
      >
      <a
        v-if="model.next_cursor"
        id="timeline-older-events"
        :href="
          timelineHref(missionId, {
            ...model.query,
            before_at: model.next_cursor.at,
            before_id: model.next_cursor.id,
            event_id: '',
          })
        "
        class="btn btn-sm"
        >Older events</a
      >
    </nav>
    <div class="grid items-start gap-4 xl:grid-cols-[minmax(0,1fr)_24rem]">
      <aside
        id="timeline-event-detail"
        ref="details"
        tabindex="-1"
        aria-label="Selected event"
        class="min-w-0 space-y-4 border border-base-300 bg-base-200/35 p-4 focus-visible:outline focus-visible:outline-primary xl:sticky xl:top-4 xl:col-start-2 xl:row-start-1"
      >
        <p v-if="model.selected_status === 'none'" class="text-sm text-base-content/65">
          Select an event to inspect its identity and references.
        </p>
        <p
          v-else-if="model.selected_status === 'unavailable'"
          id="timeline-event-unavailable"
          role="status"
          class="text-sm text-warning"
        >
          This event is unavailable in the current mission.
        </p>
        <a
          v-if="model.selected_status === 'unavailable'"
          id="timeline-clear-unavailable"
          :href="selectionHref('')"
          class="btn btn-ghost btn-sm"
          >Clear selection</a
        >
        <template v-if="selected">
          <h2 class="break-words font-semibold">{{ selected.title }}</h2>
          <p v-if="selected.summary" class="break-words text-sm">{{ selected.summary }}</p>
          <div class="flex flex-wrap gap-2">
            <a id="timeline-clear-selection" :href="selectionHref('')" class="btn btn-ghost btn-sm"
              >Clear selection</a
            >
            <CadenceClipboardButton
              button_id="timeline-copy-event"
              :clipboard_text="selectionHref(selected.id)"
              button_class="btn btn-sm"
              icon="hero-link"
              label="Copy event link"
            />
          </div>
          <dl class="space-y-3 text-sm">
            <div>
              <dt class="hud-label">Event identity</dt>
              <dd id="timeline-selected-event-id" class="mt-1 break-all font-mono text-xs">
                {{ selected.id }}
              </dd>
            </div>
            <div>
              <dt class="hud-label">Occurred</dt>
              <dd class="mt-1 break-all">
                <time :datetime="selected.occurred_at">{{ selected.occurred_at }}</time>
              </dd>
            </div>
            <div>
              <dt class="hud-label">Kind</dt>
              <dd class="mt-1 break-all">{{ selected.kind }}</dd>
            </div>
            <div v-if="selected.status">
              <dt class="hud-label">Status</dt>
              <dd class="mt-1 break-all">{{ selected.status }}</dd>
            </div>
            <div>
              <dt class="hud-label">Source record</dt>
              <dd class="mt-1 break-all">{{ selected.source.kind }} · {{ selected.source.id }}</dd>
            </div>
            <div v-if="selected.subject.id">
              <dt class="hud-label">Subject</dt>
              <dd class="mt-1 break-all">
                {{ selected.subject.kind }} · {{ selected.subject.id }}
              </dd>
            </div>
            <template v-for="key in referenceKeys" :key="key"
              ><div v-if="selected.references[key]">
                <dt class="hud-label">{{ referenceLabels[key] }}</dt>
                <dd class="mt-1 break-all font-mono text-xs">{{ selected.references[key] }}</dd>
              </div></template
            >
          </dl>
        </template>
      </aside>
      <section
        aria-label="Mission events"
        class="min-w-0 border border-base-300 bg-base-100 xl:col-start-1 xl:row-start-1"
      >
        <p
          v-if="!model.events.length"
          id="mission-timeline-events-empty"
          class="p-6 text-sm text-base-content/65"
        >
          {{
            model.errors.length
              ? "Apply valid filters to read events."
              : "No events match in this history page."
          }}
        </p>
        <ul id="mission-timeline-events" class="divide-y divide-base-300">
          <li
            v-for="row in model.events"
            :key="row.id"
            :data-event-id="row.id"
            :data-event-category="row.category"
          >
            <a
              :href="selectionHref(row.id)"
              class="block space-y-2 p-4 hover:bg-primary/5 focus-visible:outline focus-visible:outline-primary"
              :aria-current="selected?.id === row.id ? 'true' : undefined"
            >
              <div class="flex flex-wrap items-start justify-between gap-2 text-xs">
                <time :datetime="row.occurred_at" class="font-mono">{{ row.occurred_at }}</time>
                <span
                  >{{ row.category }}<span v-if="row.severity"> · {{ row.severity }}</span></span
                >
              </div>
              <h2 class="break-words text-sm font-semibold">{{ row.title }}</h2>
              <p v-if="row.summary" class="break-words text-sm text-base-content/65">
                {{ row.summary }}
              </p>
              <p class="break-all font-mono text-xs text-base-content/60">{{ row.kind }}</p>
            </a>
          </li>
        </ul>
      </section>
    </div>
  </div>
</template>
