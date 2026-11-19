<script setup lang="ts">
import { ApCallout, ApField, ApSelect } from "@/ui";
import type { AddDraft, ProviderOptions } from "./providers.ts";

/** Add provider's fields: a granted account, a name, the booking mode (bounded asks two more). */
defineProps<{ options: ProviderOptions; errors: Readonly<Record<string, string>> }>();
const draft = defineModel<AddDraft>({ required: true });
const set = <K extends keyof AddDraft>(key: K, value: AddDraft[K]) =>
  (draft.value = { ...draft.value, [key]: value });
const grants = (o: ProviderOptions) =>
  o.grants.map((g) => ({ value: g.id, label: `${g.account.name} · ${g.account.provider.label}` }));
const modes = (o: ProviderOptions) =>
  o.policy_modes.flatMap((m) =>
    m.key === "unrecognized" ? [] : [{ value: m.key, label: m.label }],
  );
</script>

<template>
  <ApCallout v-if="options.grants.length === 0" tone="info"
    >No provider account is granted to this mission yet. An org admin grants one in Provider
    accounts.</ApCallout
  >
  <ApSelect
    :model-value="draft.grant"
    label="Account"
    :options="grants(options)"
    placeholder="Choose…"
    @update:model-value="set('grant', $event)"
  />
  <ApField
    :model-value="draft.name"
    label="Name"
    required
    :error="errors['display_name'] ?? null"
    @update:model-value="set('name', $event)"
  />
  <ApSelect
    :model-value="draft.mode"
    label="Bookings"
    :options="modes(options)"
    placeholder="Choose…"
    @update:model-value="set('mode', $event)"
  />
  <template v-if="draft.mode === 'bounded_automatic'">
    <ApField
      :model-value="draft.substitutions"
      label="Stations it may swap in"
      mono
      hint="Comma-separated station refs."
      @update:model-value="set('substitutions', $event)"
    />
    <ApField
      :model-value="draft.retainedMinutes"
      label="Shortest pass worth keeping"
      unit="minutes"
      inputmode="numeric"
      @update:model-value="set('retainedMinutes', $event)"
    />
  </template>
</template>
