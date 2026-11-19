<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import type { ApiResult } from "@/api";
import { ApButton, ApCallout, ApSheet } from "@/ui";
import type { DataSource } from "./api.ts";
import CredentialSheet from "./CredentialSheet.vue";
import { health, sourceFailure, tsdbJobs } from "./present.ts";
import { probeSource, setSourceEnabled, startTsdbJob } from "./writes.ts";

/** L11 W2 enable/disable, W4 probe, W5 rotate, W6 TSDB jobs (dedicated BYO TSDBs only). */
const props = defineProps<{ missionId: MissionId; source: DataSource }>();
const emit = defineEmits<{ done: [note: { tone: "nominal" | "crit"; text: string }] }>();
const key = computed(() => ({ missionId: props.missionId, sourceId: props.source.id }));
const busy = ref(false);
const credential = ref<InstanceType<typeof CredentialSheet> | null>(null);
const confirm = ref<InstanceType<typeof ApSheet> | null>(null);
const jobs = computed(() => tsdbJobs(props.source));
const enabled = computed(() => props.source.state !== "disabled");

async function run<T>(call: () => Promise<ApiResult<T>>, said: (v: T) => string) {
  if (busy.value) return;
  busy.value = true;
  try {
    const r = await call();
    emit(
      "done",
      r.ok
        ? { tone: "nominal", text: said(r.value) }
        : { tone: "crit", text: sourceFailure(r.error) },
    );
  } finally {
    busy.value = false;
  }
}
const toggle = () =>
  run(
    () => setSourceEnabled(key.value, !enabled.value),
    (s) =>
      s.state === "disabled" ? "Disabled. It stops taking data until you enable it." : "Enabled.",
  );
const probe = () =>
  run(
    () => probeSource(key.value),
    (p) =>
      `Probed: ${health({ ...p.source, health: p.probe.health }).text}${p.probe.reason ? ` · ${p.probe.reason}` : ""}.`,
  );
const job = (kind: "provision" | "reconcile" | "deprovision") => {
  confirm.value?.close();
  return run(
    () => startTsdbJob(key.value, kind),
    (r) => (r.run ? "Started. Its progress shows under Runs." : "Reconciled. Nothing queued."),
  );
};
</script>

<template>
  <div class="flex flex-wrap gap-2">
    <ApButton :disabled="busy" disabled-reason="Working…" @click="toggle">{{
      enabled ? "Disable" : "Enable"
    }}</ApButton>
    <ApButton :disabled="busy" disabled-reason="Working…" @click="probe">Probe now</ApButton>
    <ApButton
      v-if="source.credentials_ref !== undefined && source.kind === 'byo_tsdb'"
      :disabled="busy"
      disabled-reason="Working…"
      @click="credential?.open()"
      >Rotate credential…</ApButton
    >
    <ApButton
      v-if="jobs.includes('provision')"
      :disabled="busy"
      disabled-reason="Working…"
      @click="job('provision')"
      >Provision</ApButton
    >
    <ApButton
      v-if="jobs.includes('reconcile')"
      :disabled="busy"
      disabled-reason="Working…"
      @click="job('reconcile')"
      >Reconcile</ApButton
    >
    <ApButton
      v-if="jobs.includes('deprovision')"
      variant="danger"
      :disabled="busy"
      disabled-reason="Working…"
      @click="confirm?.open()"
      >Deprovision…</ApButton
    >
  </div>
  <CredentialSheet
    ref="credential"
    :mission-id="missionId"
    :source="source"
    @done="emit('done', $event)"
  />
  <ApSheet ref="confirm" title="Deprovision this store?" width="narrow">
    <ApCallout tone="caution"
      >Cadence removes the store it provisioned for this source. Telemetry kept there stops being
      readable from it.</ApCallout
    >
    <template #footer>
      <ApButton variant="ghost" @click="confirm?.close()">Cancel</ApButton>
      <ApButton variant="danger" @click="job('deprovision')">Deprovision</ApButton>
    </template>
  </ApSheet>
</template>
