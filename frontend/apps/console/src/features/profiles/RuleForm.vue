<script setup lang="ts">
import type { Station } from "@/features/stations/index.ts";
import { ApButton, ApChip, ApField, ApSelect } from "@/ui";
import { directions, roles, tokens, type RuleDraft } from "./rulesDraft.ts";

/** One rule: label, name template, stations (chips), legs (direction + role), enabled. */
const props = defineProps<{ stations: readonly Station[]; index: number }>();
const rule = defineModel<RuleDraft>({ required: true });
defineEmits<{ remove: [] }>();
const stationLabel = (id: string) => {
  const s = props.stations.find((x) => x.id === id);
  return s ? (s.code ?? s.display_name) : id;
};
const available = () =>
  props.stations.filter(
    (s) => s.lifecycle_state === "active" && !rule.value.stationIds.includes(s.id),
  );
const patch = (p: Partial<RuleDraft>) => (rule.value = { ...rule.value, ...p });
</script>

<template>
  <fieldset class="m-0 flex flex-col gap-3 border border-hairline p-4">
    <legend class="ap-label px-1">Rule {{ index + 1 }}</legend>
    <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
      <ApField
        :model-value="rule.label"
        label="Label"
        @update:model-value="patch({ label: $event })"
      />
      <ApField
        :model-value="rule.nameTemplate"
        label="Route name"
        mono
        :hint="`Tokens: ${tokens.join(' ')}`"
        @update:model-value="patch({ nameTemplate: $event })"
      />
    </div>
    <div class="flex flex-col gap-1.5">
      <span class="ap-label">Stations</span>
      <div class="flex flex-wrap items-center gap-2">
        <ApChip
          v-for="id in rule.stationIds"
          :key="id"
          removable
          :remove-label="`Remove ${stationLabel(id)}`"
          @remove="patch({ stationIds: rule.stationIds.filter((s) => s !== id) })"
          >{{ stationLabel(id) }}</ApChip
        >
        <div class="w-56">
          <ApSelect
            model-value=""
            label="Add station"
            hidden-label
            placeholder="+ station"
            :options="
              available().map((s) => ({
                value: s.id,
                label: `${s.code ?? ''} ${s.display_name}`.trim(),
              }))
            "
            @update:model-value="$event && patch({ stationIds: [...rule.stationIds, $event] })"
          />
        </div>
      </div>
    </div>
    <div v-for="(leg, i) in rule.legs" :key="i" class="flex flex-wrap items-end gap-3">
      <div class="w-40">
        <ApSelect
          :model-value="leg.direction"
          :label="`Leg ${i + 1} direction`"
          :options="
            directions.map((d) => ({ value: d, label: d === 'downlink' ? 'Downlink' : 'Uplink' }))
          "
          @update:model-value="
            patch({
              legs: rule.legs.map((l, j) => (j === i && $event ? { ...l, direction: $event } : l)),
            })
          "
        />
      </div>
      <div class="w-40">
        <ApSelect
          :model-value="leg.role"
          label="Role"
          :options="roles.map((r) => ({ value: r, label: r[0]?.toUpperCase() + r.slice(1) }))"
          @update:model-value="
            patch({
              legs: rule.legs.map((l, j) => (j === i && $event ? { ...l, role: $event } : l)),
            })
          "
        />
      </div>
      <ApButton
        size="compact"
        variant="ghost"
        @click="patch({ legs: rule.legs.filter((_, j) => j !== i) })"
        >Remove leg</ApButton
      >
    </div>
    <div class="flex flex-wrap gap-2">
      <ApButton
        size="compact"
        @click="patch({ legs: [...rule.legs, { direction: 'uplink', role: 'primary' }] })"
        >Add leg</ApButton
      >
      <ApButton size="compact" variant="ghost" @click="patch({ enabled: !rule.enabled })">{{
        rule.enabled ? "Disable rule" : "Enable rule"
      }}</ApButton>
      <ApButton size="compact" variant="danger" @click="$emit('remove')">Remove rule</ApButton>
    </div>
  </fieldset>
</template>
