<script setup lang="ts">
import { computed } from "vue";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import { ApCallout } from "@/ui";
import DiffPanel from "./DiffPanel.vue";
import DiffStrip from "./DiffStrip.vue";
import ImportVerdict from "./ImportVerdict.vue";
import RolloutPanel from "./RolloutPanel.vue";
import { ARTIFACT_LIVE } from "./artifact.ts";
import ImportRunFile from "./ImportRunFile.vue";
import { formatBytes, type ImportRunDetail } from "./importRun.ts";

/** File line, verdict, stats, diff (when available) and diagnostics for one import run. */
const props = defineProps<{ run: ImportRunDetail }>();
// Staging a rollout needs manage_mission, which the server grants to organization admins (qa #4).
const scope = useMissionScope();
const session = useSession();
const canStage = computed(() => canAdministerOrganization(session, scope.value.organization));
const fileLine = computed(() =>
  [
    props.run.file.name,
    props.run.file.format_label,
    props.run.file.size_bytes === null ? null : formatBytes(props.run.file.size_bytes),
  ]
    .filter((p): p is string => p !== null)
    .join(" · "),
);
</script>

<template>
  <p class="m-0 text-md text-text-3">
    <span class="font-mono text-readout">{{ fileLine }}</span>
    <ImportRunFile v-if="ARTIFACT_LIVE && run.file.artifact" :artifact="run.file.artifact" />
  </p>
  <ImportVerdict :run="run" />
  <DiffStrip v-if="run.status === 'succeeded'" :run="run" />
  <DiffPanel v-if="run.diff" :diff="run.diff" :base-number="run.base_revision?.number ?? null" />
  <ApCallout v-else-if="run.status === 'succeeded'" tone="info">{{
    run.base_revision
      ? `This revision couldn't be compared with rev ${run.base_revision.number}, so there's no diff.`
      : "This is the database's first revision, so there's nothing to compare it with."
  }}</ApCallout>
  <RolloutPanel
    v-if="canStage && run.status === 'succeeded' && run.revision"
    :revision="run.revision"
    :breaking="run.diff?.summary.breaking ?? 0"
  />
</template>
