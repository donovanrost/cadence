<script setup lang="ts">
import { computed } from "vue";
import { unshownLine, type Unshown } from "@/api/index.ts";
import { ApButton, ApCallout } from "@/ui";
import { unshownWords } from "./unshown.ts";

/**
 * U86: items a list couldn't read, at the top of that list (a dropped item's priority isn't
 * known). Reload picks up a newer console if there is one; Technical details lists each item's
 * kind and id as sent, never its payload.
 */
const props = defineProps<{ unshown: readonly Unshown[] }>();
const lines = computed(() => props.unshown.map(unshownLine));
const reload = () => window.location.reload();
</script>

<template>
  <ApCallout v-if="unshown.length > 0" tone="caution">
    <span class="flex flex-col gap-1">
      <span>{{ unshownWords(unshown.length) }}</span>
      <details class="text-xs text-text-3">
        <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
        <p v-for="(t, i) in lines" :key="i" class="m-0 font-mono break-all">{{ t }}</p>
      </details>
    </span>
    <template #action>
      <ApButton size="compact" variant="ghost" @click="reload">Reload</ApButton>
    </template>
  </ApCallout>
</template>
