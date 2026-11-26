<script setup lang="ts">
import { computed, ref } from "vue";
import { RouterLink, useRoute, useRouter } from "vue-router";
import { useMissionScope } from "@/shell";
import {
  formatShort,
  plural,
  ApBreadcrumb,
  ApEmptyState,
  ApField,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApTable,
  type ApColumn,
  type ApCrumb,
} from "@/ui";
import { refetchKeepingFocus } from "../focus-fallback.ts";
import MoreMenu from "../viewer/MoreMenu.vue";
import { kindWord, type LibraryRow } from "./api.ts";
import RenameSheet from "./RenameSheet.vue";
import RetireSheet from "./RetireSheet.vue";
import { useLibraryList } from "./useLibrary.ts";

/** ux Dashboards.md › Where it sits: the library belongs to Dashboards, so it crumbs back. */
const crumbs: readonly ApCrumb[] = [
  { label: "Dashboards", to: { name: "ops.dashboards" } },
  { label: "Library" },
];

/**
 * Dashboards › Library (ux Dashboards.md § Library): reusable widgets, Name · Kind · Used in N
 * dashboards · Updated. The name opens the item; Rename and Delete sit in the row menu (editors).
 */
const scope = useMissionScope();
const route = useRoute();
const router = useRouter();
const missionId = computed(() => scope.value.mission.id);
const q = computed({
  get: () => (typeof route.query.q === "string" ? route.query.q : ""),
  set: (v: string) =>
    router
      .replace({ query: { ...route.query, q: v.trim() || undefined, page: undefined } })
      .catch((e: unknown) => console.error("Navigation failed", e)),
});
const page = computed(() => Math.max(1, Number(route.query.page) || 1));
const list = useLibraryList(missionId, q, page);
/** A5: a deleted widget's row leaves with its ⋯; focus goes to the page heading. */
const refetchAfterDelete = refetchKeepingFocus(() => list.state.value, list.refetch);
const rename = ref<InstanceType<typeof RenameSheet> | null>(null);
const retire = ref<InstanceType<typeof RetireSheet> | null>(null);
const columns: readonly ApColumn[] = [
  { key: "name", label: "Name" },
  { key: "kind", label: "Kind" },
  { key: "used", label: "Used in", align: "end" },
  { key: "updated", label: "Updated" },
  { key: "actions", label: "Actions", hiddenLabel: true, align: "end" },
];
const updated = (row: LibraryRow) =>
  row.updated_at
    ? `${formatShort(new Date(row.updated_at))}${row.updated_by?.name ? ` · ${row.updated_by.name}` : ""}`
    : "—";
const actions = [
  { id: "rename", label: "Rename…" },
  { id: "delete", label: "Delete…" },
] as const;
function act(row: LibraryRow, id: "rename" | "delete") {
  if (id === "rename") rename.value?.open(row);
  // Known count > 0: the sheet asks the server, which names the dashboards (Q10).
  else retire.value?.open(row);
}
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col gap-3 max-console:overflow-auto">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApPageHeader :label="`${scope.mission.name} · dashboards`" title="Library" />
    <div class="w-72 max-md:w-full">
      <ApField
        v-model="q"
        label="Search the library"
        hidden-label
        type="search"
        placeholder="Name or description"
      />
    </div>
    <ApPanel
      index="L1"
      title="Reusable widgets"
      :meta="
        list.state.value.status === 'ready'
          ? plural(list.state.value.value.total, 'widget')
          : undefined
      "
      pane
      flush
    >
      <ApRemote :state="list.state.value" loading-label="LOADING LIBRARY…" @retry="list.refetch">
        <template #default="{ value }">
          <ApEmptyState
            v-if="value.items.length === 0"
            :headline="q ? `Nothing in the library matches “${q}”` : 'The library is empty'"
            :announce="q !== ''"
            sentence="Save a widget to the library from a dashboard's editor to reuse it."
          />
          <ApTable
            v-else
            :columns="columns"
            :rows="value.items"
            :row-key="(r) => r.id"
            caption="Library"
          >
            <template #cell-name="{ row }">
              <RouterLink
                :to="{ name: 'ops.dashboards.library.item', params: { itemId: row.id } }"
                class="max-md:hit-44 text-readout no-underline hover:text-bright hover:underline"
                >{{ row.name }}</RouterLink
              >
            </template>
            <template #cell-kind="{ row }"
              ><span class="text-text-2">{{ kindWord(row.kind) }}</span></template
            >
            <template #cell-used="{ row }"
              ><span
                class="font-mono"
                :class="row.used_by_count ? 'text-readout' : 'text-text-3'"
                >{{ row.used_by_count ? plural(row.used_by_count, "dashboard") : "Unused" }}</span
              ></template
            >
            <template #cell-updated="{ row }"
              ><span class="text-text-3">{{ updated(row) }}</span></template
            >
            <template #cell-actions="{ row }">
              <MoreMenu
                v-if="value.can_edit"
                :items="actions"
                :label="`Actions for ${row.name}`"
                @select="(id) => act(row, id)"
              />
            </template>
          </ApTable>
        </template>
      </ApRemote>
    </ApPanel>
    <RenameSheet ref="rename" :mission-id="missionId" @done="list.refetch" />
    <RetireSheet ref="retire" :mission-id="missionId" @done="refetchAfterDelete" />
  </div>
</template>
