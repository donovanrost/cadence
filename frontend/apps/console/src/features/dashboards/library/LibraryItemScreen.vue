<script setup lang="ts">
import { computed, ref } from "vue";
import { RouterLink, useRoute, useRouter } from "vue-router";
import { useMissionScope } from "@/shell";
import {
  formatShort,
  ApBreadcrumb,
  ApButton,
  ApCallout,
  ApKeyValue,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApTag,
  type ApCrumb,
} from "@/ui";
import { kindWord, usedInWords } from "./api.ts";
import { previewOf } from "./preview.ts";
import RenameSheet from "./RenameSheet.vue";
import RetireSheet from "./RetireSheet.vue";
import { useLibraryItem } from "./useLibrary.ts";

/** ux Dashboards.md › Where it sits: Dashboards / Library / this widget. */
const crumbsFor = (name: string): readonly ApCrumb[] => [
  { label: "Dashboards", to: { name: "ops.dashboards" } },
  { label: "Library", to: { name: "ops.dashboards.library" } },
  { label: name },
];

/**
 * A library widget (ux Dashboards.md § Library): its versions (pick one to preview it), a
 * definition preview, where it's used (links), and Rename / Delete for editors.
 */
const scope = useMissionScope();
const route = useRoute("ops.dashboards.library.item");
const router = useRouter();
const missionId = computed(() => scope.value.mission.id);
const itemId = computed(() =>
  typeof route.params.itemId === "string" ? route.params.itemId : null,
);
const version = computed(() => {
  const v = Number(route.query.version);
  return Number.isInteger(v) && v > 0 ? v : null;
});
const item = useLibraryItem(missionId, itemId, version);
const rename = ref<InstanceType<typeof RenameSheet> | null>(null);
const retire = ref<InstanceType<typeof RetireSheet> | null>(null);
const pick = (v: number) =>
  router
    .replace({ query: { ...route.query, version: String(v) } })
    .catch((e: unknown) => console.error("Navigation failed", e));
const when = (iso: string | null, who: string | null | undefined) =>
  iso ? `${formatShort(new Date(iso))}${who ? ` · ${who}` : ""}` : "—";
function retired() {
  router
    .replace({ name: "ops.dashboards.library" })
    .catch((e: unknown) => console.error("Navigation failed", e));
}
</script>

<template>
  <ApRemote :state="item.state.value" loading-label="LOADING WIDGET…" @retry="item.refetch">
    <template #default="{ value }">
      <div class="flex min-h-0 flex-1 flex-col gap-3 max-console:overflow-auto">
        <ApBreadcrumb :crumbs="crumbsFor(value.item.name)" />
        <ApPageHeader :label="`${scope.mission.name} · dashboard library`" :title="value.item.name">
          <template #status><ApTag state="neutral" :label="kindWord(value.item.kind)" /></template>
          <div class="flex flex-wrap gap-2">
            <template v-if="value.can_edit">
              <ApButton size="compact" variant="secondary" @click="rename?.open(value.item)"
                >Rename</ApButton
              >
              <ApButton
                size="compact"
                variant="danger"
                @click="retire?.open(value.item, value.used_by.dashboards)"
                >Delete</ApButton
              >
            </template>
          </div>
        </ApPageHeader>
        <p v-if="value.item.description" class="m-0 text-text-2">{{ value.item.description }}</p>
        <div class="grid grid-cols-1 gap-3 console:grid-cols-[minmax(0,1fr)_340px]">
          <ApPanel index="L2" :title="`Preview · v${value.version.version}`" flush>
            <div class="flex flex-col gap-3 p-4">
              <ApCallout v-if="value.version.version !== value.item.latest_version" tone="info">
                An older version. Dashboards that pin it still show it this way.
              </ApCallout>
              <template v-if="previewOf(value.version.definition_json)">
                <ApKeyValue
                  :items="[
                    {
                      key: 'kind',
                      label: 'Kind',
                      value: previewOf(value.version.definition_json)?.kind ?? '',
                    },
                    {
                      key: 'title',
                      label: 'Title',
                      value: previewOf(value.version.definition_json)?.title ?? 'Untitled',
                    },
                    { key: 'reads', label: 'Reads', value: 'Nothing bound' },
                  ]"
                >
                  <!-- ux Dashboards.md › Library: the point in mono, then where it's read. -->
                  <template
                    v-if="previewOf(value.version.definition_json)?.reads.length"
                    #value-reads
                  >
                    <span
                      v-for="r in previewOf(value.version.definition_json)?.reads"
                      :key="r.point"
                      class="block"
                      ><span class="font-mono text-readout">{{ r.point }}</span
                      ><!-- A real space (qa: innerText and screen readers), not template whitespace. -->{{
                        r.on ? ` ${r.on}` : ""
                      }}</span
                    >
                  </template>
                </ApKeyValue>
                <details
                  v-if="previewOf(value.version.definition_json)?.settings.length"
                  class="text-sm text-text-3"
                >
                  <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
                  <ul class="m-0 list-none p-0 pt-1 font-mono">
                    <li v-for="s in previewOf(value.version.definition_json)?.settings" :key="s">
                      {{ s }}
                    </li>
                  </ul>
                </details>
              </template>
              <ApCallout v-else tone="off">This version's definition can't be read here.</ApCallout>
            </div>
          </ApPanel>
          <div class="flex flex-col gap-3">
            <ApPanel index="L3" title="Versions" :meta="String(value.versions.length)" flush>
              <ol class="m-0 list-none p-0">
                <li
                  v-for="v in value.versions"
                  :key="v.version"
                  class="flex items-baseline gap-3 border-t border-hairline-faint px-4 py-2 first:border-t-0"
                >
                  <button
                    type="button"
                    class="max-md:hit-44 cursor-pointer border-0 bg-transparent p-0 font-mono text-readout hover:underline"
                    :aria-current="v.version === value.version.version ? 'true' : undefined"
                    @click="pick(v.version)"
                  >
                    v{{ v.version }}
                  </button>
                  <span class="min-w-0 flex-1 truncate text-sm text-text-2">{{
                    v.summary || "No summary"
                  }}</span>
                  <span class="font-mono text-xs text-text-4">{{
                    when(v.saved_at, v.saved_by?.name)
                  }}</span>
                </li>
              </ol>
            </ApPanel>
            <ApPanel index="L4" title="Used in" flush>
              <div class="flex flex-col gap-2 p-4">
                <p class="m-0 text-text-2">{{ usedInWords(value.used_by.dashboards) }}</p>
                <ul
                  v-if="value.used_by.dashboards.length"
                  class="m-0 flex list-none flex-col gap-1 p-0"
                >
                  <li v-for="dash in value.used_by.dashboards" :key="dash.id">
                    <RouterLink
                      :to="{ name: 'ops.dashboard', params: { dashboardId: dash.id } }"
                      class="max-md:hit-44 text-readout hover:underline"
                      >{{ dash.name }}</RouterLink
                    >
                  </li>
                </ul>
              </div>
            </ApPanel>
          </div>
        </div>
        <RenameSheet ref="rename" :mission-id="missionId" @done="item.refetch" />
        <RetireSheet ref="retire" :mission-id="missionId" @done="retired" />
      </div>
    </template>
  </ApRemote>
</template>
