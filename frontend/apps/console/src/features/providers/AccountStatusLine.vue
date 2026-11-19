<script setup lang="ts">
import { computed } from "vue";
import { ApTag, formatShort } from "@/ui";
import { statusTag, type ProviderAccount } from "./api.ts";
import { INGESTION_LABEL, ingestionReadBack } from "./ingestion.ts";

/** Provider account detail · status tag, its detail, last successful call. */
const props = defineProps<{ account: ProviderAccount }>();
/** U77 read-back: never an interval unless the configuration states one (none is read yet). */
const updates = computed(() =>
  ingestionReadBack(props.account.event_ingestion_mode, props.account.provider.label),
);
</script>

<template>
  <div class="flex flex-wrap items-center gap-3">
    <ApTag v-bind="statusTag(account)" />
    <span v-if="account.status_detail" class="text-sm text-text-3">{{
      account.status_detail
    }}</span>
    <span class="font-mono text-sm text-text-3"
      >Last success
      {{ account.last_success_at ? formatShort(new Date(account.last_success_at)) : "never" }}</span
    >
    <span v-if="updates" class="text-sm text-text-2"
      >{{ INGESTION_LABEL }} ·
      <span :class="updates.off ? 'text-caution-text' : ''">{{ updates.value }}</span
      ><template v-if="updates.off"> · {{ updates.off }}</template></span
    >
  </div>
</template>
