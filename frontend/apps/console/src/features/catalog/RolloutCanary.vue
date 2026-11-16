<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { fetchSpacecraftDirectory } from "@/features/spacecraft/index.ts";
import { ApChip, ApRemote, ApSelect, focusAfterRemove } from "@/ui";

/** C3 a few spacecraft first: the Compose C1 pattern (chips plus an "Add spacecraft…" select). */
const props = defineProps<{ missionId: MissionId }>();
const ids = defineModel<readonly string[]>({ required: true });
const missionId = computed(() => props.missionId);
const { state, refetch } = useRemoteQuery(missionId, fetchSpacecraftDirectory);
const all = computed(() => (state.value.status === "ready" ? state.value.value.spacecraft : []));
const nameOf = (id: string) => all.value.find((s) => s.id === id)?.name ?? id;
const options = computed(() =>
  all.value
    .filter((s) => !ids.value.includes(s.id))
    .map((s) => ({ value: s.id, label: s.scid === null ? s.name : `${s.name} · SCID ${s.scid}` })),
);
// a11y A5: removing a chip takes its focused ×; land on the next chip's ×, else Add spacecraft.
const box = ref<HTMLElement | null>(null);
function remove(id: string) {
  const at = ids.value.indexOf(id);
  ids.value = ids.value.filter((x) => x !== id);
  void focusAfterRemove(box.value, 'button[aria-label^="Remove "]', at, () =>
    box.value?.querySelector("select"),
  );
}
</script>

<template>
  <ApRemote :state="state" loading-label="Loading spacecraft…" @retry="refetch">
    <div ref="box" class="flex flex-wrap items-center gap-2">
      <ApChip
        v-for="id in ids"
        :key="id"
        removable
        :remove-label="`Remove ${nameOf(id)}`"
        @remove="remove(id)"
        >{{ nameOf(id) }}</ApChip
      >
      <div class="w-64">
        <ApSelect
          model-value=""
          label="Add spacecraft"
          hidden-label
          mono
          placeholder="Add spacecraft…"
          :options="options"
          @update:model-value="$event && (ids = [...ids, $event])"
        />
      </div>
    </div>
  </ApRemote>
</template>
