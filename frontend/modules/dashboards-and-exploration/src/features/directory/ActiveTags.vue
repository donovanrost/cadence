<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";

defineProps<{ tags: readonly string[] }>();
const emit = defineEmits<{ toggle: [tag: string]; clear: [] }>();
</script>

<template>
  <div class="flex flex-wrap items-center gap-2 text-sm">
    <span class="text-base-content/70">Tagged</span>
    <CadenceButton
      v-for="tag in tags"
      :key="tag"
      size="xs"
      variant="outline"
      :aria-label="`Remove tag ${tag}`"
      @click="emit('toggle', tag)"
    >
      {{ tag }}<CadenceIcon name="hero-x-mark" size="xs" />
    </CadenceButton>
    <CadenceButton size="xs" variant="quiet" @click="emit('clear')">Clear filters</CadenceButton>
  </div>
</template>
