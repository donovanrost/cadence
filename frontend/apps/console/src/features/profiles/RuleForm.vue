<script setup lang="ts">
import type { Station } from "@/features/stations/index.ts";
import { ApButton, ApField } from "@/ui";
import RuleLegs from "./RuleLegs.vue";
import RuleStations from "./RuleStations.vue";
import { tokens, unknownTokens, type RuleDraft } from "./rulesDraft.ts";

/** One rule: label, name template, stations (chips), legs (direction + role), enabled. */
defineProps<{ stations: readonly Station[]; index: number }>();
const rule = defineModel<RuleDraft>({ required: true });
defineEmits<{ remove: [] }>();
const patch = (p: Partial<RuleDraft>) => (rule.value = { ...rule.value, ...p });
/** a11y A6: an unknown token is a typed-in error, so it sits on Route name (aria-invalid). */
const tokenError = () => {
  const unknown = unknownTokens(rule.value.nameTemplate);
  return unknown.length > 0 ? `Unknown token .` : null;
};
</script>

<template>
  <fieldset class="m-0 flex flex-col gap-3 border border-hairline p-4">
    <legend class="ap-label px-1">Rule {{ index + 1 }}</legend>
    <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
      <ApField
        :model-value="rule.label"
        label="Label"
        required
        @update:model-value="patch({ label: $event })"
      />
      <ApField
        :model-value="rule.nameTemplate"
        label="Route name"
        mono
        :hint="`Tokens: ${tokens.join(' ')}`"
        :error="tokenError()"
        @update:model-value="patch({ nameTemplate: $event })"
      />
    </div>
    <RuleStations
      :model-value="rule.stationIds"
      :stations="stations"
      @update:model-value="patch({ stationIds: $event })"
    />
    <RuleLegs :model-value="rule.legs" @update:model-value="patch({ legs: $event })" />
    <div class="flex flex-wrap gap-2">
      <ApButton
        size="compact"
        data-add-leg
        @click="patch({ legs: [...rule.legs, { direction: 'uplink', role: 'primary' }] })"
        >Add leg</ApButton
      >
      <ApButton size="compact" variant="ghost" @click="patch({ enabled: !rule.enabled })">{{
        rule.enabled ? "Disable rule" : "Enable rule"
      }}</ApButton>
      <ApButton size="compact" variant="danger" data-remove-rule @click="$emit('remove')"
        >Remove rule</ApButton
      >
    </div>
  </fieldset>
</template>
