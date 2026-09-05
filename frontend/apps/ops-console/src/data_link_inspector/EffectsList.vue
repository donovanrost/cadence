<script setup lang="ts">
import type { PropType } from "vue";
import type { EffectPresentation } from "./presentation_types";

defineProps({
  effects: { type: Array as PropType<EffectPresentation[]>, required: true },
  id: { type: String, required: true },
  key_attribute: { type: String, required: true },
});
</script>

<template>
  <div :id="id" class="grid grid-cols-1 gap-1 text-[0.68rem] sm:grid-cols-2">
    <div v-for="effect in effects" :key="String(effect.attrs[key_attribute])" v-bind="effect.attrs">
      <div :class="effect.label.class">{{ effect.label.text }}</div>
      <div v-bind="effect.summary.attrs">{{ effect.summary.text }}</div>
    </div>
  </div>
</template>
