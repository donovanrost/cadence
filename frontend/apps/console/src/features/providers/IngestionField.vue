<script setup lang="ts">
import { computed } from "vue";
import { ApCallout, ApSelect } from "@/ui";
import {
  INGESTION_LABEL,
  ingestionDescription,
  ingestionHint,
  ingestionNote,
  ingestionOptions,
  type IngestionMode,
  type OfferedMode,
} from "./ingestion.ts";

/**
 * U77 'Booking updates' on Add and Edit account: the choice, what it means, and Off's caution or
 * what an edit changes. `from` is the account's current mode on Edit, null on Add.
 */
const props = defineProps<{
  provider: string;
  from: IngestionMode | null;
  error?: string | null | undefined;
}>();
const mode = defineModel<OfferedMode>({ required: true });
const note = computed(() => ingestionNote(mode.value, props.from, props.provider));
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <ApSelect
      v-model="mode"
      :label="INGESTION_LABEL"
      :hint="ingestionHint(provider)"
      :options="ingestionOptions(provider)"
      :error="error ?? null"
    />
    <p class="m-0 text-sm text-text-2">{{ ingestionDescription(mode, provider) }}</p>
    <ApCallout v-if="note" :tone="note.tone">{{ note.text }}</ApCallout>
  </div>
</template>
