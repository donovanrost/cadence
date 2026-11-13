<script setup lang="ts">
import { computed } from "vue";
import { ApField, ApSelect, plural } from "@/ui";
import { ceiling, type GrantDraft, type Grants } from "./grants.ts";

/** Grant automation's fields; each limit's hint is the active policy's ceiling. */
const props = defineProps<{ grants: Grants; errors: Readonly<Record<string, string>> }>();
const draft = defineModel<GrantDraft>({ required: true });
const identities = computed(() =>
  props.grants.service_identities
    .filter((i) => i.state === "active")
    .map((i) => ({ value: i.id, label: i.name })),
);
const set = <K extends keyof GrantDraft>(key: K, value: GrantDraft[K]) =>
  (draft.value = { ...draft.value, [key]: value });
const l = computed(() => props.grants.limits);
</script>

<template>
  <ApSelect
    :model-value="draft.identity"
    label="Service identity"
    :options="identities"
    placeholder="Choose…"
    :error="errors['service_identity_id'] ?? null"
    @update:model-value="set('identity', $event)"
  />
  <ApField
    :model-value="draft.hours"
    label="Plans ahead up to"
    unit="hours"
    inputmode="numeric"
    :hint="ceiling(l.maximum_horizon_seconds, (s) => `${s / 3600} hours`)"
    :error="errors['maximum_horizon_seconds'] ?? null"
    @update:model-value="set('hours', $event)"
  />
  <ApField
    :model-value="draft.contacts"
    label="Contacts per plan, at most"
    inputmode="numeric"
    :hint="ceiling(l.maximum_contacts, (n) => plural(n, 'contact'))"
    :error="errors['maximum_contacts'] ?? null"
    @update:model-value="set('contacts', $event)"
  />
  <ApField
    :model-value="draft.concurrency"
    label="At once, at most"
    inputmode="numeric"
    :hint="ceiling(l.maximum_execution_concurrency, (n) => `${n} at once`)"
    :error="errors['maximum_execution_concurrency'] ?? null"
    @update:model-value="set('concurrency', $event)"
  />
  <ApField
    :model-value="draft.days"
    label="Valid for"
    unit="days"
    hint="1 to 365 days."
    :error="errors['valid_days'] ?? null"
    inputmode="numeric"
    @update:model-value="set('days', $event)"
  />
</template>
