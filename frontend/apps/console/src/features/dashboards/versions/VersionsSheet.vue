<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApCallout, ApSheet } from "@/ui";
import ChangeList from "../editor/ChangeList.vue";
import JsonDiffView from "./JsonDiffView.vue";
import VersionRows from "./VersionRows.vue";
import { useVersions } from "./useVersions.ts";

/**
 * ⋯ › Versions (Grafana-style): history, compare any two, restore one as a new current version.
 * Restore isn't offered while editing (the draft would sit on a stale base).
 */
const props = defineProps<{ missionId: string; dashboardId: string; canRestore: boolean }>();
const emit = defineEmits<{ restored: [version: number] }>();
const v = useVersions(
  computed(() => props.missionId),
  computed(() => props.dashboardId),
);
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const selected = ref<number[]>([]);
const json = ref(false);
const pending = ref<number | null>(null);
const pair = computed(() => (selected.value.length === 2 ? selected.value : null));

function open() {
  selected.value = [];
  json.value = false;
  pending.value = null;
  v.comparison.value = null;
  void v.load();
  sheet.value?.open();
}
function toggle(version: number) {
  selected.value = selected.value.includes(version)
    ? selected.value.filter((x) => x !== version)
    : [...selected.value, version].slice(-2);
}
async function confirmRestore() {
  if (pending.value === null) return;
  const made = await v.restoreVersion(pending.value);
  pending.value = null;
  if (made !== null) emit("restored", made);
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Versions" width="wide">
    <div class="flex flex-col gap-3">
      <ApCallout v-if="v.error.value" tone="crit">{{
        v.error.value.kind === "unauthenticated" ? "Signed out." : v.error.value.message
      }}</ApCallout>
      <ApCallout v-if="pending !== null" tone="caution">
        Restore v{{ pending }}? It becomes a new current version for everyone; nothing is deleted.
        <template #action>
          <span class="flex gap-2">
            <ApButton
              size="compact"
              variant="primary"
              :disabled="v.busy.value"
              disabled-reason="Restoring…"
              @click="confirmRestore"
              >Restore</ApButton
            >
            <ApButton size="compact" variant="secondary" @click="pending = null">Cancel</ApButton>
          </span>
        </template>
      </ApCallout>
      <VersionRows
        v-if="v.list.value"
        :rows="v.list.value.versions"
        :selected="selected"
        :can-restore="canRestore"
        @toggle="toggle"
        @restore="pending = $event"
      />
      <section v-if="v.comparison.value" class="flex flex-col gap-2">
        <h3 class="m-0 font-display text-xs uppercase tracking-label text-text-4">
          v{{ v.comparison.value.from }} → v{{ v.comparison.value.to }}
        </h3>
        <ChangeList :changes="v.comparison.value.changes" empty="These versions are the same." />
        <ApButton size="compact" variant="ghost" @click="json = !json">{{
          json ? "Hide JSON" : "Show JSON"
        }}</ApButton>
        <JsonDiffView
          v-if="json"
          :before="v.comparison.value.fromJson"
          :after="v.comparison.value.toJson"
        />
      </section>
    </div>
    <template #footer>
      <ApButton
        variant="secondary"
        class="mr-auto"
        :disabled="!pair"
        disabled-reason="Pick two versions."
        @click="pair && v.compare(pair[0] ?? 0, pair[1] ?? 0)"
        >Compare</ApButton
      >
      <ApButton variant="primary" @click="sheet?.close()">Close</ApButton>
    </template>
  </ApSheet>
</template>
