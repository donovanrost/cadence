<script setup lang="ts">
import { ApCallout, ApField, ApTextarea } from "@/ui";

/** U32 sheet body: re-ask line, then the fields and consequence for the chosen action. */
defineProps<{
  booked: boolean;
  provider: string;
  errors: Readonly<Record<string, string>>;
  failure: string | null;
}>();
const reference = defineModel<string>("reference", { required: true });
const note = defineModel<string>("note", { required: true });
</script>

<template>
  <p class="m-0 text-base text-text-2">
    Cadence asks {{ provider }} once more first. If {{ provider }} answers, its answer is used and
    nothing is marked.
  </p>
  <p v-if="!booked" class="m-0 text-base text-text-2">
    Then Cadence sends {{ provider }} a cancel. The pass becomes a gap that Re-plan can fill.
  </p>
  <ApField
    v-if="booked"
    v-model="reference"
    :label="`${provider} booking reference`"
    mono
    required
    :error="errors['provider_reference'] ?? null"
  />
  <ApTextarea
    v-model="note"
    label="Note"
    required
    :placeholder="booked ? 'How did you confirm it?' : 'How do you know it isn\'t booked?'"
    :error="errors['note'] ?? null"
  />
  <p v-if="booked" class="m-0 text-sm text-text-3">
    The pass counts as booked on your word. Uplink stays unconfirmed until {{ provider }} confirms
    it.
  </p>
  <ApCallout v-if="failure" tone="caution" role="alert">{{ failure }}</ApCallout>
</template>
