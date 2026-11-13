<script setup lang="ts">
import { computed, onScopeDispose, ref, watch } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { plural, ApButton, ApEmptyState, ApField, ApRemote, ApTag } from "@/ui";
import { fetchCatalog } from "../api.ts";

/** `+ Add command`: search the active catalog (M17); Enter or click adds the command. */
const emit = defineEmits<{ add: [commandId: string] }>();
const scope = useMissionScope();
const q = ref("");
const term = ref("");
let timer: ReturnType<typeof setTimeout> | null = null;
watch(q, (v) => {
  if (timer !== null) clearTimeout(timer);
  timer = setTimeout(() => (term.value = v.trim()), 120);
});
onScopeDispose(() => {
  if (timer !== null) clearTimeout(timer);
});
const catalog = useRemoteQuery(
  // A typed key (§12 A4): compared by value, no JSON round trip or cast.
  computed(() => ({ m: scope.value.mission.id, q: term.value })),
  (k, signal) => fetchCatalog(k.m, k.q, signal),
);
function addFirst() {
  const s = catalog.state.value;
  const first = s.status === "ready" ? s.value.commands[0] : undefined;
  if (first) emit("add", first.id);
}
</script>

<template>
  <div class="flex flex-col gap-2">
    <form @submit.prevent="addFirst">
      <ApField
        v-model="q"
        label="Add command"
        type="search"
        mono
        placeholder="Search the catalog, e.g. SET_"
      />
    </form>
    <ApRemote
      :state="catalog.state.value"
      loading-label="LOADING CATALOG…"
      @retry="catalog.refetch"
    >
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.state === 'not_active'"
          state="off"
          headline="No active command catalog"
          sentence="Import and activate a catalog in Setup before commanding."
        >
          <ApButton size="compact" :to="{ name: 'setup.catalog' }">Open catalog</ApButton>
        </ApEmptyState>
        <ul v-else class="m-0 max-h-56 list-none overflow-auto border border-hairline p-0">
          <li
            v-for="cmd in value.commands"
            :key="cmd.id"
            class="border-t border-hairline-faint first:border-t-0"
          >
            <button
              type="button"
              class="flex min-h-11 w-full cursor-pointer items-center gap-3 px-3 py-1.5 text-left hover:bg-raised"
              @click="emit('add', cmd.id)"
            >
              <span class="flex-none font-mono text-md text-readout">{{ cmd.name }}</span>
              <span class="min-w-0 flex-1 truncate text-md text-text-3">{{
                cmd.description ?? ""
              }}</span>
              <ApTag v-if="cmd.hazardous" state="crit" label="Hazardous" />
              <span class="flex-none font-mono text-xs whitespace-nowrap text-text-4">{{
                plural(cmd.argument_count, "arg")
              }}</span>
            </button>
          </li>
          <li v-if="value.commands.length === 0" class="px-3 py-2 text-md text-text-3">
            No commands match “{{ term }}”.
          </li>
        </ul>
      </template>
    </ApRemote>
  </div>
</template>
