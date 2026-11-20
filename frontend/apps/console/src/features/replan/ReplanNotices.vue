<script setup lang="ts">
import type { ReviewAfter } from "@/features/scheduling/review-run.ts";
import { ApCallout, outcomeRole } from "@/ui";

/**
 * The re-plan's outcomes of the person's own acts (a11y B6, #276, ux): a refused or failed action
 * is an alert; the apply's result is read politely when it went well, an alert when it didn't.
 */
defineProps<{ error: string | null; applied: ReviewAfter | null }>();
</script>

<template>
  <ApCallout v-if="error" tone="caution" role="alert">{{ error }}</ApCallout>
  <ApCallout v-if="applied" :tone="applied.tone" :role="outcomeRole(applied.tone)">{{
    applied.text
  }}</ApCallout>
</template>
