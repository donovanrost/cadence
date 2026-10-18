<script setup lang="ts">
import { onBeforeUnmount, ref, shallowRef, watch } from "vue";
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import LimitStateList from "../../shared/LimitStateList.vue";
import DefinitionEvidence from "../../shared/DefinitionEvidence.vue";
import { href } from "../../shared/contracts";
import { admitDocument, type PostureDocument, type PosturePort } from "./contracts";
const props = defineProps<{ initial: PostureDocument; port: PosturePort }>(),
  page = shallowRef(props.initial),
  loading = ref(false),
  error = ref("");
const search = ref(String(page.value.query.q)),
  severity = ref(String(page.value.query.severity)),
  spacecraft = ref(String(page.value.query.spacecraft)),
  craftSearch = ref(String(page.value.query.spacecraft_q));
let alive = true,
  generation = 0;
function accept(value: unknown) {
  const next = admitDocument(value);
  if (
    !next ||
    ["organization_id", "mission_id", "actor_id", "installation_id"].some(
      (k) =>
        next.context[k as keyof typeof next.context] !==
        props.initial.context[k as keyof typeof next.context],
    )
  )
    return false;
  page.value = next;
  return true;
}
watch(
  () => props.initial,
  (value) => {
    if (!accept(value))
      error.value = "Current posture could not be admitted. Showing the last loaded evidence.";
  },
);
async function refresh() {
  const n = ++generation;
  loading.value = true;
  error.value = "";
  try {
    const value = await props.port.read();
    if (!alive || n !== generation) return;
    if (!accept(value)) throw Error();
  } catch {
    if (alive && n === generation)
      error.value = "Current posture could not be loaded. Showing the last loaded evidence.";
  } finally {
    if (alive && n === generation) loading.value = false;
  }
}
function navigate(target: string, event?: MouseEvent) {
  if (
    event &&
    (event.ctrlKey || event.metaKey || event.altKey || event.shiftKey || event.button !== 0)
  )
    return;
  event?.preventDefault();
  props.port.navigate(target);
}
function filter() {
  navigate(
    href(page.value.links.self, {
      ...page.value.query,
      q: search.value,
      severity: severity.value,
      spacecraft: spacecraft.value,
      page: 1,
    }),
  );
}
function findCraft() {
  navigate(
    href(page.value.links.self, {
      ...page.value.query,
      spacecraft_q: craftSearch.value,
      spacecraft_page: 1,
    }),
  );
}
onBeforeUnmount(() => {
  alive = false;
  generation++;
});
useManagementHeader("/missions/:mission_id/applications/:application_key/:surface_id", {
  title: "Current limit posture",
  description: "Latest evaluated state per spacecraft and point.",
});
</script>
<template>
  <div id="limits-posture-page" class="space-y-5">
    <div class="flex flex-wrap items-center justify-between gap-3 text-sm">
      <div class="flex gap-4">
        <a
          :href="page.links.applications"
          class="link"
          @click="navigate(page.links.applications, $event)"
          >Mission applications</a
        ><a :href="page.links.manage" class="link" @click="navigate(page.links.manage, $event)"
          >Limit definitions</a
        >
      </div>
      <button
        id="refresh-limit-posture"
        class="btn btn-ghost btn-sm"
        :disabled="loading"
        @click="refresh"
      >
        {{ loading ? "Refreshing…" : "Refresh evidence" }}
      </button>
    </div>
    <p
      v-if="error"
      id="limits-posture-error"
      role="alert"
      class="border border-warning/40 p-3 text-sm"
    >
      {{ error }}
    </p>
    <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
      <div v-for="(count, tone) in page.counts" :key="tone" class="border border-base-300/50 p-3">
        <p class="text-xs uppercase tracking-wider">{{ tone }}</p>
        <p class="font-mono text-2xl">{{ count }}</p>
      </div>
    </div>
    <p class="text-xs text-base-content/60">
      Counts reflect the selected search and spacecraft scope across all pages. Timestamps describe
      the evaluated sample; loading this view does not establish data freshness.
    </p>
    <CadenceCard body-class="space-y-4 p-5">
      <form
        id="limit-posture-filters"
        class="grid items-end gap-3 sm:grid-cols-2 lg:grid-cols-4"
        @submit.prevent="filter"
      >
        <CadenceField label="Find a point or set"
          ><input
            id="posture-search"
            v-model="search"
            maxlength="240"
            type="search"
            class="input input-bordered w-full" /></CadenceField
        ><CadenceField label="Severity"
          ><select id="posture-severity" v-model="severity" class="select select-bordered w-full">
            <option value="">All states</option>
            <option value="red">Red</option>
            <option value="yellow">Yellow</option>
            <option value="blue">Blue</option>
            <option value="green">Green</option>
          </select></CadenceField
        ><CadenceField label="Spacecraft scope"
          ><select
            id="posture-spacecraft"
            v-model="spacecraft"
            class="select select-bordered w-full"
          >
            <option value="">All spacecraft and mission states</option>
            <option value="mission">Mission states</option>
            <option
              v-if="
                page.query.spacecraft &&
                page.query.spacecraft !== 'mission' &&
                !page.spacecraft.items.some((x) => x.id === page.query.spacecraft)
              "
              :value="page.query.spacecraft"
            >
              {{ page.spacecraft_filter }}
            </option>
            <option v-for="c in page.spacecraft.items" :key="c.id" :value="c.id">
              {{ c.label }}
            </option>
          </select></CadenceField
        ><button id="apply-posture-filters" class="btn btn-sm">Apply filters</button>
      </form>
      <details>
        <summary class="cursor-pointer text-xs">
          Find more spacecraft · {{ page.spacecraft.total_count }}
        </summary>
        <form class="mt-3 flex items-end gap-2" @submit.prevent="findCraft">
          <CadenceField label="Find spacecraft" wrapper-class="min-w-0 flex-1"
            ><input
              id="posture-spacecraft-search"
              v-model="craftSearch"
              type="search"
              maxlength="240"
              class="input input-bordered w-full" /></CadenceField
          ><button class="btn btn-sm">Find</button>
        </form>
        <nav aria-label="Posture spacecraft pages" class="mt-3 flex justify-between gap-2 text-xs">
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
        <h2 class="font-semibold">Evaluated states</h2>
        <span class="font-mono text-xs"
          >{{ page.states.total_count }} states · {{ page.spacecraft_filter }}</span
        >
      </div>
      <p
        v-if="!page.states.items.length"
        id="limits-posture-empty"
        class="text-sm text-base-content/60"
      >
        No evaluated states match this view. Saving a definition does not itself create a new
        evaluated state.
      </p>
      <LimitStateList :items="page.states.items" :navigate="navigate" />
      <nav aria-label="Limit state pages" class="flex justify-between gap-2 text-xs">
        <a
          v-if="page.states.previous_href"
          :href="page.states.previous_href"
          class="link"
          @click="navigate(page.states.previous_href, $event)"
          >Previous states</a
        ><span>Page {{ page.states.page }}</span
        ><a
          v-if="page.states.next_href"
          :href="page.states.next_href"
          class="link"
          @click="navigate(page.states.next_href, $event)"
          >Next states</a
        >
      </nav>
    </CadenceCard>
    <DefinitionEvidence :selection="page.selection" :navigate="navigate" />
  </div>
</template>
