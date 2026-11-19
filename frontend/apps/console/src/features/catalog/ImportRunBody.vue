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
import { formatBytes, sameDatabaseMatch, type ImportRunDetail } from "./importRun.ts";
import MatchedDetails from "./MatchedDetails.vue";
import { matchVerdict, otherDatabaseVerdict } from "./matchedWords.ts";

/** File line, verdict, stats, diff (when available) and diagnostics for one import run. */
const props = defineProps<{ run: ImportRunDetail }>();
// Staging a rollout needs manage_mission, which the server grants to organization admins (qa #4).
const scope = useMissionScope();
const session = useSession();
const canStage = computed(() => canAdministerOrganization(session, scope.value.organization));
// #119 U99: a same-database match has no diff of its own; only an approved match offers its
// rollout, with the breaking count unknown here (null, never 0: U102's fallback).
const match = computed(() => sameDatabaseMatch(props.run));
const rollout = computed(() => {
  const m = match.value;
  if (m) return m.revision && matchVerdict(m).rollout ? m.revision : null;
  const own = props.run.status === "succeeded" ? props.run.revision : null;
  const other = props.run.matched_revision;
  // Another database's match: its own revision rolls out only when the shared model is approved.
  if (own && other && !otherDatabaseVerdict(own, other).rollout) return null;
  return own;
});
const breaking = computed(() => (match.value ? null : (props.run.diff?.summary.breaking ?? 0)));
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
  <DiffStrip v-if="run.status === 'succeeded' && !match" :run="run" />
  <DiffPanel v-if="run.diff" :diff="run.diff" :base-number="run.base_revision?.number ?? null" />
  <ApCallout v-else-if="run.status === 'succeeded' && !match" tone="info">{{
    run.base_revision
      ? `This revision couldn't be compared with rev ${run.base_revision.number}, so there's no diff.`
      : "This is the database's first revision, so there's nothing to compare it with."
  }}</ApCallout>
  <RolloutPanel v-if="canStage && rollout" :revision="rollout" :breaking="breaking" />
  <MatchedDetails v-if="run.matched_revision" :match="run.matched_revision" />
</template>
