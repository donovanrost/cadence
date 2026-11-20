<script setup lang="ts">
import { computed } from "vue";
import { ApField } from "@/ui";
import { actionsNarrowable, type NarrowDraft } from "./grant-narrow.ts";
import { grantActions, type Grant } from "./grants.ts";

/** Narrow…'s fields, labelled as the grant sheet's (U105 names the fields by these labels). */
const props = defineProps<{ grant: Grant; errors: Readonly<Record<string, string>> }>();
const draft = defineModel<NarrowDraft>({ required: true });
const WORDS: Readonly<Record<(typeof grantActions)[number], string>> = {
  plan: "Plan",
  repair: "Repair",
  execute: "Book",
  submit: "Submit",
  approve: "Approve",
};
const actions = computed(() =>
  actionsNarrowable(props.grant)
    ? props.grant.allowed_actions.filter(
        (a): a is (typeof grantActions)[number] => a !== "unrecognized",
      )
    : [],
);
const set = <K extends keyof NarrowDraft>(key: K, value: NarrowDraft[K]) =>
  (draft.value = { ...draft.value, [key]: value });
const toggle = (a: string, on: boolean) =>
  set("actions", on ? [...draft.value.actions, a] : draft.value.actions.filter((x) => x !== a));
function onToggle(a: string, event: Event) {
  if (event.target instanceof HTMLInputElement) toggle(a, event.target.checked);
}
const now = (text: string) => `Now ${text}. Choose the same or less.`;
</script>

<template>
  <fieldset v-if="actions.length > 0" class="m-0 flex flex-col gap-1.5 border-0 p-0">
    <legend class="ap-label mb-1">Can</legend>
    <label v-for="a in actions" :key="a" class="flex items-center gap-2 text-md text-text-2">
      <input
        type="checkbox"
        class="accent-[var(--color-readout)] [color-scheme:dark]"
        :checked="draft.actions.includes(a)"
        @change="onToggle(a, $event)"
      />
      {{ WORDS[a] }}
    </label>
    <p v-if="errors['actions']" class="m-0 text-sm text-crit-text">{{ errors["actions"] }}</p>
  </fieldset>
  <ApField
    :model-value="draft.hours"
    label="Plans ahead up to"
    unit="hours"
    inputmode="numeric"
    :hint="now(`${grant.maximum_horizon_seconds / 3600} hours`)"
    :error="errors['hours'] ?? null"
    @update:model-value="set('hours', $event)"
  />
  <ApField
    :model-value="draft.contacts"
    label="Contacts per plan, at most"
    inputmode="numeric"
    :hint="now(String(grant.maximum_contacts))"
    :error="errors['contacts'] ?? null"
    @update:model-value="set('contacts', $event)"
  />
  <ApField
    :model-value="draft.concurrency"
    label="At once, at most"
    inputmode="numeric"
    :hint="now(String(grant.maximum_execution_concurrency))"
    :error="errors['concurrency'] ?? null"
    @update:model-value="set('concurrency', $event)"
  />
  <ApField
    v-if="grant.validity_seconds !== null"
    :model-value="draft.days"
    label="Valid for"
    unit="days"
    inputmode="numeric"
    :hint="now(`${grant.validity_seconds / 86400} days, from approval`)"
    :error="errors['days'] ?? null"
    @update:model-value="set('days', $event)"
  />
</template>
