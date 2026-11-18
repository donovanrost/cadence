<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { nextTick, ref } from "vue";
import { RouterLink } from "vue-router";
import { describeApiError, isError } from "@/api";
import { ApButton, ApCallout, ApSheet, refocusFirst } from "@/ui";
import { retireItem, usedByOf, usedInWords, type UsedBy } from "./api.ts";

/**
 * Delete a library widget (Q10): refused while a current dashboard version uses it, naming them
 * as links ("Used in 3 dashboards: A, B, C."); once unused it retires: gone from the library,
 * versions kept so older dashboard versions still render. Audited server-side.
 */
const props = defineProps<{ missionId: MissionId }>();
const emit = defineEmits<{ done: [] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const target = ref<{
  id: string;
  name: string;
  version: number;
  updatedAt: string | null;
} | null>(null);
const usedBy = ref<UsedBy["dashboards"]>([]);
const error = ref<string | null>(null);
const busy = ref(false);

/** `known`: the item page's used_by, so a used widget is refused before asking the server. */
function open(
  item: { id: string; name: string; latest_version: number; updated_at: string | null },
  known: UsedBy["dashboards"] = [],
) {
  target.value = {
    id: item.id,
    name: item.name,
    version: item.latest_version,
    updatedAt: item.updated_at,
  };
  usedBy.value = known;
  error.value = null;
  sheet.value?.open();
}
async function retire() {
  const t = target.value;
  if (!t || busy.value || usedBy.value.length) return;
  busy.value = true;
  const r = await retireItem(props.missionId, t.id, t.version, t.updatedAt);
  busy.value = false;
  // 404: someone retired it meanwhile, so it's already what was asked (api ffd5c6d69).
  if (r.ok || r.error.kind === "not_found") {
    sheet.value?.close();
    emit("done");
    return;
  }
  const used = usedByOf(r.error);
  if (used) {
    // A5: the refusal takes Delete away; focus goes to the line that says why.
    usedBy.value = used;
    await nextTick();
    refocusFirst(document.querySelector<HTMLElement>("[data-retire-used]"));
  } else
    error.value =
      r.error.kind === "forbidden"
        ? "Dashboard editors manage the library."
        : isError(r.error, "library_item_changed")
          ? "Someone changed this widget meanwhile. Close and check it again."
          : describeApiError(r.error);
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" :title="`Delete ${target?.name ?? 'library widget'}?`">
    <template v-if="usedBy.length">
      <ApCallout tone="caution" data-retire-used>
        {{ usedInWords(usedBy) }} Replace or detach it there first; detaching copies it into that
        dashboard.
      </ApCallout>
      <ul class="m-0 flex list-none flex-col gap-1 p-0">
        <li v-for="dash in usedBy" :key="dash.id">
          <RouterLink
            :to="{ name: 'ops.dashboard', params: { dashboardId: dash.id } }"
            class="max-md:hit-44 text-readout hover:underline"
            @click="sheet?.close()"
            >{{ dash.name }}</RouterLink
          >
          <span class="text-text-3">
            · {{ dash.placements }} {{ dash.placements === 1 ? "placement" : "placements" }}</span
          >
        </li>
      </ul>
    </template>
    <p v-else class="m-0 text-base text-readout">
      It leaves the library. Its versions stay stored, so older dashboard versions still show it.
    </p>
    <ApCallout v-if="error" tone="crit">{{ error }}</ApCallout>
    <template #footer>
      <ApButton variant="secondary" class="mr-auto" @click="sheet?.close()">{{
        usedBy.length ? "Close" : "Keep it"
      }}</ApButton>
      <ApButton
        v-if="!usedBy.length"
        variant="danger"
        :disabled="busy"
        disabled-reason="Deleting…"
        @click="retire"
        >Delete</ApButton
      >
    </template>
  </ApSheet>
</template>
