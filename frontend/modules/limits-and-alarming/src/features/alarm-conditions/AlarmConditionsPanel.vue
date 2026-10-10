<script setup lang="ts">
import { onBeforeUnmount, ref, shallowRef } from "vue";
import type {
  OpsPageContext,
  OpsPageNavigationPort,
  OpsPageReadPort,
} from "@cadence/plugin-sdk/ops-pages";
import { useOpsHeader } from "@cadence/plugin-sdk/page-header";
import { serverHref } from "@cadence/plugin-sdk/routes";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import LimitStateList from "../../shared/LimitStateList.vue";
import { admitAlarmDocument, alarmHref, type AlarmDocument, type AlarmQuery } from "./contracts";
const props = defineProps<{
  model: AlarmDocument;
  context: OpsPageContext;
  port: OpsPageNavigationPort;
  readPort: OpsPageReadPort;
}>();
const page = shallowRef(props.model),
  reading = ref(false),
  error = ref("");
const filters = ref({ ...props.model.query });
let active = true,
  generation = 0;
useOpsHeader("/missions/:mission_id/ops/alarms", () => ({
  description: "Latest evaluated limit states across the mission.",
  actions: [
    {
      id: "definitions",
      label: "Limit definitions",
      href: serverHref(page.value.links.definitions),
    },
    { id: "posture", label: "Current posture", href: serverHref(page.value.links.posture) },
  ],
  refresh: { run: refresh, pending: reading.value },
}));
async function refresh() {
  if (reading.value) return;
  const n = ++generation;
  reading.value = true;
  error.value = "";
  try {
    const value = await props.readPort.read();
    if (!active || n !== generation) return;
    const next = admitAlarmDocument(value, props.context);
    if (
      !next ||
      Object.entries(page.value.query).some(
        ([key, value]) => next.query[key as keyof AlarmQuery] !== value,
      )
    )
      throw Error();
    page.value = next;
  } catch {
    if (active && n === generation)
      error.value = "Current conditions could not be loaded. Showing the last loaded evidence.";
  } finally {
    if (active && n === generation) reading.value = false;
  }
}
function navigate(href: string, event?: MouseEvent) {
  if (
    event &&
    (event.ctrlKey || event.metaKey || event.altKey || event.shiftKey || event.button !== 0)
  )
    return;
  event?.preventDefault();
  props.port.navigate(href);
}
function apply() {
  navigate(alarmHref(page.value.links.self, { ...filters.value, page: 1 }));
}
function reset() {
  const query: AlarmQuery = {
    severity: "all",
    state: "all",
    spacecraft_id: "all",
    query: "",
    page: 1,
    spacecraft_page: 1,
    spacecraft_query: "",
  };
  navigate(alarmHref(page.value.links.self, query));
}
function findCraft() {
  navigate(
    alarmHref(page.value.links.self, {
      ...page.value.query,
      spacecraft_query: filters.value.spacecraft_query,
      spacecraft_page: 1,
    }),
  );
}
onBeforeUnmount(() => {
  active = false;
  generation++;
});
</script>
<template>
  <div id="ops-alarms-page" class="space-y-5">
    <p
      v-if="error"
      id="alarm-conditions-error"
      role="alert"
      class="border border-warning/40 p-3 text-sm"
    >
      {{ error }}
    </p>
    <div id="alarm-summary" class="grid grid-cols-2 gap-3 sm:grid-cols-4">
      <div v-for="(count, tone) in page.counts" :key="tone" class="border border-base-300/50 p-3">
        <p class="text-xs uppercase tracking-wider">{{ tone }}</p>
        <p class="font-mono text-2xl">{{ count }}</p>
      </div>
    </div>
    <p class="text-xs text-base-content/60">
      Counts cover every page in the selected search, condition state and spacecraft scope, before
      severity filtering. Loaded {{ page.loaded_at }}; sample timestamps below describe the
      evaluated evidence.
    </p>
    <CadenceCard body-class="space-y-4 p-5 min-w-0">
      <form
        id="alarm-filters"
        class="grid min-w-0 grid-cols-1 items-end gap-3 sm:grid-cols-2 lg:grid-cols-4"
        @submit.prevent="apply"
      >
        <CadenceField label="Severity" wrapper-class="fieldset mb-3 min-w-0"
          ><select
            id="alarm-severity"
            v-model="filters.severity"
            class="select select-bordered w-full"
          >
            <option value="all">All severities</option>
            <option value="critical">Critical</option>
            <option value="warning">Warning</option>
            <option value="info">Info</option>
            <option value="nominal">Nominal</option>
          </select></CadenceField
        >
        <CadenceField label="Condition state" wrapper-class="fieldset mb-3 min-w-0"
          ><select id="alarm-state" v-model="filters.state" class="select select-bordered w-full">
            <option value="all">All conditions</option>
            <option value="active">Active</option>
            <option value="nominal">Nominal</option>
          </select></CadenceField
        >
        <CadenceField label="Spacecraft scope" wrapper-class="fieldset mb-3 min-w-0"
          ><select
            id="alarm-spacecraft"
            v-model="filters.spacecraft_id"
            class="select select-bordered w-full"
          >
            <option value="all">All spacecraft and mission states</option>
            <option value="mission">Mission states</option>
            <option
              v-if="
                page.query.spacecraft_id !== 'all' &&
                page.query.spacecraft_id !== 'mission' &&
                !page.spacecraft.items.some((x) => x.id === page.query.spacecraft_id)
              "
              :value="page.query.spacecraft_id"
            >
              {{ page.spacecraft_filter }}
            </option>
            <option v-for="c in page.spacecraft.items" :key="c.id" :value="c.id">
              {{ c.label }}
            </option>
          </select></CadenceField
        >
        <CadenceField label="Find a point or set" wrapper-class="fieldset mb-3 min-w-0"
          ><input
            id="alarm-query"
            v-model="filters.query"
            type="search"
            maxlength="240"
            class="input input-bordered w-full"
        /></CadenceField>
        <div class="flex flex-wrap gap-3">
          <button id="apply-alarm-filters" class="btn btn-sm">Apply filters</button
          ><button
            id="alarm-filter-reset"
            type="button"
            class="btn btn-ghost btn-sm"
            @click="reset"
          >
            Reset filters
          </button>
        </div>
      </form>
      <details>
        <summary class="cursor-pointer text-xs">
          Find more spacecraft · {{ page.spacecraft.total_count }}
        </summary>
        <form class="mt-3 flex items-end gap-2" @submit.prevent="findCraft">
          <CadenceField label="Find spacecraft" wrapper-class="min-w-0 flex-1"
            ><input
              id="alarm-spacecraft-query"
              v-model="filters.spacecraft_query"
              type="search"
              maxlength="240"
              class="input input-bordered w-full" /></CadenceField
          ><button class="btn btn-sm">Find</button>
        </form>
        <nav aria-label="Alarm spacecraft pages" class="mt-3 flex justify-between gap-2 text-xs">
          <a
            v-if="page.spacecraft.previous_href"
            :href="page.spacecraft.previous_href"
            class="link"
            @click="navigate(page.spacecraft.previous_href, $event)"
            >Previous spacecraft</a
          ><span>Page {{ page.spacecraft.page }}</span
          ><a
            v-if="page.spacecraft.next_href"
            :href="page.spacecraft.next_href"
            class="link"
            @click="navigate(page.spacecraft.next_href, $event)"
            >Next spacecraft</a
          >
        </nav>
      </details>
    </CadenceCard>
    <CadenceCard body-class="space-y-4 p-5 min-w-0">
      <div class="flex flex-wrap justify-between gap-2">
        <h2 class="font-semibold">Evaluated conditions</h2>
        <span class="font-mono text-xs"
          >{{ page.states.total_count }} conditions · {{ page.spacecraft_filter }}</span
        >
      </div>
      <p
        v-if="!page.states.items.length"
        id="alarm-conditions-empty"
        class="text-sm text-base-content/60"
      >
        No evaluated conditions match this view. Saving limits does not itself create an evaluated
        state.
      </p>
      <LimitStateList :items="page.states.items" :navigate="navigate" />
      <nav aria-label="Alarm condition pages" class="flex justify-between gap-2 text-xs">
        <a
          v-if="page.states.previous_href"
          :href="page.states.previous_href"
          class="link"
          @click="navigate(page.states.previous_href, $event)"
          >Previous conditions</a
        ><span>Page {{ page.states.page }}</span
        ><a
          v-if="page.states.next_href"
          :href="page.states.next_href"
          class="link"
          @click="navigate(page.states.next_href, $event)"
          >Next conditions</a
        >
      </nav>
    </CadenceCard>
  </div>
</template>
