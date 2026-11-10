<script setup lang="ts">
import { ApTag, formatShort } from "@/ui";
import { statusTag, type ProviderAccount } from "./api.ts";

/** Provider account detail · status tag, its detail, last successful call. */
defineProps<{ account: ProviderAccount }>();
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
  </div>
</template>
