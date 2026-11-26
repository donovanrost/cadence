<script setup lang="ts">
import { ApCallout } from "@/ui";
import type { Worded } from "./grant-words.ts";

/**
 * A refused grant act (U105): its sentence as an alert (a11y B6), and a code the console doesn't
 * word in Technical details, never on the line itself (U20, #308).
 */
defineProps<{ refusal: Worded | null }>();
</script>

<template>
  <ApCallout v-if="refusal" tone="crit" role="alert"
    >{{ refusal.text }}
    <details v-if="refusal.code" class="mt-1 text-sm">
      <summary class="ap-label cursor-pointer">Technical details</summary>
      <p class="m-0 mt-1 font-mono text-xs text-text-3">{{ refusal.code }}</p>
    </details>
  </ApCallout>
</template>
