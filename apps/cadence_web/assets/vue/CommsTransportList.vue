<script setup lang="ts">
import { computed } from "vue";

import StatusBadge from "./StatusBadge.vue";
import CadencePaginationFrame from "./ui/components/CadencePaginationFrame.vue";
import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue";

type TransportRow = {
  id: string;
  transport_id: string;
  display_name: string;
  origin: string;
  origin_id: string;
  provider: string;
  provider_dom_id: string;
  operator_summary: string;
  operator_summary_id: string;
  endpoint: string;
  readiness_status: "info" | "ready" | "attention" | "blocked";
  readiness_label: string;
  readiness_id: string;
  version: string;
  href: string;
};

type Props = {
  rows: TransportRow[];
  search: string | null;
  sort: "display_name";
  sort_dir: "asc" | "desc";
  page: number;
  page_size: number;
  total_count: number;
};

const props = defineProps<Props>();

const lastPage = computed(() =>
  Math.max(Math.ceil(props.total_count / props.page_size), 1)
);
const firstVisible = computed(() => (props.page - 1) * props.page_size + 1);
const lastVisible = computed(() =>
  Math.min(props.page * props.page_size, props.total_count)
);
</script>

<template>
  <div>
    <div
      id="transports-toolbar"
      class="flex flex-wrap items-center justify-between gap-3 border-b border-base-300 px-4 py-2"
    >
      <form
        id="transports-toolbar-search-form"
        phx-change="search"
        class="w-64 max-w-full"
        @submit.prevent
      >
        <div class="fieldset">
          <label>
            <input
              id="transports-toolbar-search"
              name="q"
              type="search"
              :value="search ?? ''"
              placeholder="Search transports"
              class="w-full input input-sm"
              phx-debounce="300"
            />
          </label>
        </div>
      </form>
    </div>

    <CadenceTableFrame id="transports-table">
      <thead>
        <tr>
          <th
            class="hud-label"
            :aria-sort="
              sort === 'display_name' ? `${sort_dir}ending` : undefined
            "
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
                :class="[
                  'h-3 w-3',
                  sort_dir === 'asc' ? 'hero-chevron-up' : 'hero-chevron-down',
                ]"
              ></span>
            </button>
          </th>
          <th class="hud-label">Origin</th>
          <th class="hud-label">Provider</th>
          <th class="hud-label">Delivery</th>
          <th class="hud-label">Readiness</th>
          <th class="hud-label">Version</th>
        </tr>
      </thead>
      <tbody id="transports">
        <tr
          v-for="row in rows"
          :id="row.id"
          :key="row.id"
          class="border-l-2 border-l-transparent transition-colors hover:border-l-primary/60"
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
          <td>
            <span :id="row.origin_id" class="font-mono text-xs uppercase">
              {{ row.origin }}
            </span>
          </td>
          <td>
            <span :id="row.provider_dom_id">{{ row.provider }}</span>
          </td>
          <td>
            <div :id="row.operator_summary_id">{{ row.operator_summary }}</div>
            <div class="mt-1 font-mono text-xs text-base-content/50">
              {{ row.endpoint }}
            </div>
          </td>
          <td>
            <StatusBadge
              :id="row.readiness_id"
              :status="row.readiness_status"
              :label="row.readiness_label"
            />
          </td>
          <td class="font-mono text-sm text-base-content/70">
            {{ row.version }}
          </td>
        </tr>
      </tbody>
    </CadenceTableFrame>

    <p
      v-if="total_count === 0"
      class="py-6 text-center text-sm text-base-content/70"
    >
      No transports match the current search.
    </p>

    <CadencePaginationFrame
      v-if="total_count > page_size"
      id="transports-pagination"
    >
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
