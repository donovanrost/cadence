<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import { failureOutcome } from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApPanel } from "@/ui";
import { archiveDashboard, type SettingsKey } from "./api.ts";
import { usedByPlaylists } from "./present.ts";

/** General's foot (ux): Archive, danger, confirms; D3 warns (409 in_use) when playlists use it. */
const props = defineProps<{ settingsKey: SettingsKey; archived: boolean }>();
const router = useRouter();
const confirming = ref(false);
const playlists = ref<readonly string[] | null>(null);
const failure = ref<string | null>(null);
const busy = ref(false);

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
      <ApCallout v-if="playlists" tone="caution"
        >Used in {{ playlists.length === 1 ? "a playlist" : `${playlists.length} playlists` }}:
        {{ playlists.join(", ") }}. Archiving skips it there until it's restored.</ApCallout
      >
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
      <div class="flex flex-wrap gap-2">
        <ApButton v-if="!confirming" variant="danger" @click="confirming = true">Archive…</ApButton>
        <template v-else>
          <ApButton
            variant="danger"
            :disabled="busy"
            disabled-reason="Working…"
            @click="archive(playlists !== null)"
            >{{ playlists ? "Archive anyway" : "Archive the dashboard" }}</ApButton
          >
          <ApButton variant="ghost" @click="((confirming = false), (playlists = null))"
            >Keep it</ApButton
          >
        </template>
      </div>
    </div>
  </ApPanel>
  <p v-else class="m-0 text-md text-text-3">
    This dashboard is archived. Restore it from the directory.
  </p>
</template>
