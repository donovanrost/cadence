<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, onScopeDispose, ref, watch } from "vue";
import { plural, ApButton, ApEmptyState, ApField, ApRemote } from "@/ui";
import { kindWord } from "./api.ts";
import { useLibraryList } from "./useLibrary.ts";

/**
 * The editor seam (slice 8): WidgetSheet's `From library` tab mounts this; picking emits
 * `{library_item_id, version, name}` and the editor stages a library reference
 * (`add_library_widget`), not a copy, so "Used in N dashboards" stays true.
 */
const props = defineProps<{ missionId: MissionId }>();
const emit = defineEmits<{
  pick: [pick: { library_item_id: string; version: number; name: string }];
}>();
const text = ref("");
const q = ref("");
let timer: ReturnType<typeof setTimeout> | null = null;
watch(text, (v) => {
  if (timer !== null) clearTimeout(timer);
  timer = setTimeout(() => (q.value = v.trim()), 150);
});
onScopeDispose(() => {
  if (timer !== null) clearTimeout(timer);
});
const list = useLibraryList(
  computed(() => props.missionId),
  q,
  ref(1),
);
</script>

<template>
  <div class="flex flex-col gap-2">
    <ApField
      v-model="text"
      label="Search the library"
      type="search"
      placeholder="Name or description"
    />
    <ApRemote :state="list.state.value" loading-label="LOADING LIBRARY…" @retry="list.refetch">
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.items.length === 0"
          :headline="q ? `Nothing in the library matches “${q}”` : 'The library is empty'"
        />
        <ul v-else class="m-0 max-h-72 list-none overflow-auto border border-hairline p-0">
          <li
            v-for="row in value.items"
            :key="row.id"
            class="flex items-center gap-3 border-t border-hairline-faint px-3 py-2 first:border-t-0"
          >
            <span class="flex min-w-0 flex-1 flex-col">
              <span class="truncate text-readout">{{ row.name }}</span>
              <span class="truncate text-sm text-text-3"
                >{{ kindWord(row.kind) }} · v{{ row.latest_version }} ·
                {{
                  row.used_by_count ? `in ${plural(row.used_by_count, "dashboard")}` : "unused"
                }}</span
              >
            </span>
            <ApButton
              size="compact"
              variant="secondary"
              :aria-label="`Insert ${row.name}`"
              @click="
                emit('pick', {
                  library_item_id: row.id,
                  version: row.latest_version,
                  name: row.name,
                })
              "
              >Insert</ApButton
            >
          </li>
        </ul>
      </template>
    </ApRemote>
  </div>
</template>
