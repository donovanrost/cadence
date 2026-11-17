<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import type { RepairInfo } from "@/features/scheduling/index.ts";
import { windowMeta } from "./windowMeta.ts";

/** ux U76: the re-plan's window, cause, the policy's horizon and the attempt, under the title. */
const props = defineProps<{ repair: RepairInfo; now: Date; admin: boolean }>();
const meta = computed(() => windowMeta(props.repair, props.now));
</script>

<template>
  <p
    class="m-0 font-mono text-sm"
    :class="meta.last || meta.noneLeft ? 'text-caution-text' : 'text-text-2'"
    data-replan-window
  >
    {{ meta.text }}
  </p>
  <p v-if="meta.noneLeft" class="m-0 text-md text-text-2">
    {{ meta.noneLeft }}
    <RouterLink
      v-if="admin"
      :to="{ name: 'setup.contact-planning.policy' }"
      class="max-md:hit-44 text-readout underline hover:text-bright"
      >Planning policy</RouterLink
    >
  </p>
</template>
