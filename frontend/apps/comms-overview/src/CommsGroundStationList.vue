<script setup lang="ts">
import { computed } from "vue";
import CadenceListToolbarFrame from "@cadence/ui/CadenceListToolbarFrame.vue";
import CadencePaginationFrame from "@cadence/ui/CadencePaginationFrame.vue";
import CadenceTableFrame from "@cadence/ui/CadenceTableFrame.vue";

type GroundStationRow = {
  id: string;
  display_name: string;
  provider: string;
  region: string;
  ground_station_id: string;
  href: string;
};

type Props = {
  rows: GroundStationRow[];
  search: string | null;
  sort: "display_name";
  sort_dir: "asc" | "desc";
  page: number;
  page_size: number;
  total_count: number;
};

const props = defineProps<Props>();

const lastPage = computed(() => Math.max(Math.ceil(props.total_count / props.page_size), 1));
const firstVisible = computed(() => (props.page - 1) * props.page_size + 1);
const lastVisible = computed(() => Math.min(props.page * props.page_size, props.total_count));
</script>

<template>
  <div>
    <CadenceListToolbarFrame id="ground-stations-toolbar">
      <form
        id="ground-stations-toolbar-search-form"
        phx-change="search"
        class="w-64 max-w-full"
        @submit.prevent
      >
        <div class="fieldset">
          <label>
            <input
              id="ground-stations-toolbar-search"
              name="q"
              type="search"
              :value="search ?? ''"
              placeholder="Search ground stations"
              class="w-full input input-sm"
              phx-debounce="300"
            />
          </label>
        </div>
      </form>
    </CadenceListToolbarFrame>

    <CadenceTableFrame id="ground-stations-table">
      <thead>
        <tr>
          <th
            class="hud-label"
            :aria-sort="sort === 'display_name' ? `${sort_dir}ending` : undefined"
          >
            <button
              type="button"
              phx-click="sort"
              phx-value-sort="display_name"
              class="inline-flex cursor-pointer items-center gap-1 uppercase hover:text-primary"
            >
              Name
              <span
                v-if="sort === 'display_name'"
                :class="['h-3 w-3', sort_dir === 'asc' ? 'hero-chevron-up' : 'hero-chevron-down']"
              ></span>
            </button>
          </th>
          <th class="hud-label">Provider</th>
          <th class="hud-label">Region</th>
          <th class="hud-label">Station ID</th>
        </tr>
      </thead>
      <tbody id="ground-stations">
        <tr
          v-for="row in rows"
          :id="row.id"
          :key="row.id"
          class="border-l-2 border-l-transparent hover:border-l-primary/60 transition-colors"
        >
          <td class="font-medium">
            <a
              :href="row.href"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="text-primary hover:underline"
              >{{ row.display_name }}</a
            >
          </td>
          <td class="font-mono text-sm uppercase text-primary/80">{{ row.provider }}</td>
          <td class="font-mono text-sm text-base-content/70">{{ row.region }}</td>
          <td class="font-mono text-sm text-base-content/70">{{ row.ground_station_id }}</td>
        </tr>
      </tbody>
    </CadenceTableFrame>

    <p v-if="total_count === 0" class="py-6 text-center text-sm text-base-content/70">
      No ground stations match the current search.
    </p>

    <CadencePaginationFrame v-if="total_count > page_size" id="ground-stations-pagination">
      <span class="font-mono text-xs text-base-content/70">
        {{ firstVisible }}–{{ lastVisible }} of {{ total_count }}
      </span>
      <div class="flex items-center gap-1">
        <button
          type="button"
          class="btn btn-ghost btn-xs"
          phx-click="paginate"
          :phx-value-page="page - 1"
          :disabled="page <= 1"
        >
          Prev
        </button>
        <button
          type="button"
          class="btn btn-ghost btn-xs"
          phx-click="paginate"
          :phx-value-page="page + 1"
          :disabled="page >= lastPage"
        >
          Next
        </button>
      </div>
    </CadencePaginationFrame>
  </div>
</template>
