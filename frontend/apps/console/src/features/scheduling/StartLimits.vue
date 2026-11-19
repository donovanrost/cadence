<script setup lang="ts">
import { computed } from "vue";
import type { ApiError } from "@/api";
import { ApCallout } from "@/ui";
import { capLines, limitRefusal, overLimit, type StartEstimate } from "./start-limit.ts";

/**
 * U52 (ux), above Start: over the limit (caution; Start is disabled with the same sentence), each
 * template's per-run cap (caution; Start stays enabled), and Start's 422 as the backstop (crit).
 */
const props = defineProps<{ estimate: StartEstimate | null; error: ApiError | null }>();
const over = computed(() => overLimit(props.estimate));
const caps = computed(() => capLines(props.estimate));
const refused = computed(() => limitRefusal(props.error));
</script>

<template>
  <ApCallout v-if="refused" tone="crit">{{ refused }}</ApCallout>
  <ApCallout v-else-if="over" tone="caution">{{ over }}</ApCallout>
  <ApCallout v-for="line in caps" :key="line" tone="caution">{{ line }}</ApCallout>
</template>
