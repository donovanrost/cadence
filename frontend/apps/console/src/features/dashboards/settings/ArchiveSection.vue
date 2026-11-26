<script setup lang="ts">
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import { failureOutcome } from "@/features/changes/index.ts";
import { ApButton, ApInlineConfirm, ApPanel } from "@/ui";
import { archiveDashboard, type SettingsKey } from "./api.ts";
import { usedByPlaylists } from "./present.ts";

/**
 * General's foot (ux): Archive…, danger, confirms in place with the kit's confirm (A1 opens on
 * Keep it, A4 Esc, A5 focus back to Archive…). D3: when playlists use it (409 in_use), the
 * confirm says where, under the question, and the action becomes Archive anyway.
 */
const props = defineProps<{ settingsKey: SettingsKey; archived: boolean }>();
const router = useRouter();
const confirming = ref(false);
const playlists = ref<readonly string[] | null>(null);
const failure = ref<string | null>(null);
const busy = ref(false);
const refusal = computed(() =>
  playlists.value
    ? `Used in ${playlists.value.length === 1 ? "a playlist" : `${playlists.value.length} playlists`}: ${playlists.value.join(", ")}. Archiving skips it there until it's restored.`
    : failure.value,
);

async function archive(confirm: boolean) {
  busy.value = true;
  failure.value = null;
  try {
    const r = await archiveDashboard(props.settingsKey, confirm);
    if (r.ok) return void (await router.push({ name: "ops.dashboards" }));
    const used = usedByPlaylists(r.error);
    if (used) playlists.value = used;
    else failure.value = failureOutcome(r.error, "changed").sentence;
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel v-if="!archived" index="S2" title="Archive">
    <div class="flex flex-col gap-3">
      <p class="m-0 text-md text-text-3">
        Archived dashboards leave the directory; their links stop working.
      </p>
      <ApInlineConfirm
        v-model:open="confirming"
        :action="playlists ? 'Archive anyway' : 'Archive the dashboard'"
        cancel-label="Keep it"
        :busy="busy"
        busy-reason="Archiving…"
        :refusal="refusal"
        @confirm="archive(playlists !== null)"
        @cancel="((playlists = null), (failure = null))"
      >
        <template #trigger="{ attrs }">
          <ApButton variant="danger" class="self-start" v-bind="attrs">Archive…</ApButton>
        </template>
        Archive this dashboard? It leaves the directory, and its links stop working.
      </ApInlineConfirm>
    </div>
  </ApPanel>
  <p v-else class="m-0 text-md text-text-3">
    This dashboard is archived. Restore it from the directory.
  </p>
</template>
