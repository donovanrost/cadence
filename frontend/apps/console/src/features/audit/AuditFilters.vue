<script setup lang="ts">
import { ApButton, ApSegmented, ApSelect, OutcomeCallout } from "@/ui";
import type { AuditActor } from "./useAuditActor.ts";
import type { AuditExport } from "./useAuditExport.ts";

/** Audit log filters: actor, mission, kind, and Export CSV for them (SettingsAuditProviders.md). */
defineProps<{
  actor: AuditActor;
  kind: string;
  kindOptions: readonly Readonly<{ value: string; label: string }>[];
  missionOptions: readonly Readonly<{ value: string; label: string }>[];
  exporter: AuditExport;
}>();
const emit = defineEmits<{ kind: [value: string] }>();
/** ux (spec amended): one-of chips, All first; past 8 kinds or under 1100px a select, never wrapping. */
const setKind = (value: string) => emit("kind", value);
const missionId = defineModel<string>("missionId", { required: true });
</script>

<template>
  <div class="flex flex-wrap items-end gap-3">
    <ApSelect
      :model-value="actor.id.value ?? ''"
      label="Actor"
      :options="actor.options.value"
      @update:model-value="actor.set"
    />
    <ApSelect v-model="missionId" label="Mission" :options="missionOptions" />
    <div v-if="kindOptions.length <= 8" class="hidden min-[1100px]:block">
      <ApSegmented
        :model-value="kind"
        label="Kind"
        :options="kindOptions"
        @update:model-value="setKind"
      />
    </div>
    <div :class="kindOptions.length <= 8 ? 'min-[1100px]:hidden' : ''">
      <ApSelect
        :model-value="kind"
        label="Kind"
        :options="kindOptions"
        @update:model-value="setKind"
      />
    </div>
    <ApButton
      class="ml-auto"
      :disabled="exporter.busy.value"
      disabled-reason="Exporting…"
      @click="exporter.run"
      >{{ exporter.busy.value ? "Exporting…" : "Export CSV" }}</ApButton
    >
  </div>
  <OutcomeCallout v-if="exporter.note.value" :outcome="exporter.note.value" />
</template>
