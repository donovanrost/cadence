<script setup lang="ts">
import { computed } from "vue";
import type { Pass } from "./api.ts";
import { cutOffWords } from "./cutOff.ts";

/** ux U67: a quiet note (text-3, no mark, no status colour) when the pass ended mid-frame. */
const props = defineProps<{ cutOff: Pass["incomplete_at_end"] }>();
const words = computed(() => cutOffWords(props.cutOff));
</script>

<template>
  <p v-if="words" class="m-0 text-sm text-text-3">{{ words }}</p>
</template>
