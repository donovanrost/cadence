<script setup lang="ts">
defineProps<{ tags: readonly string[]; selected: readonly string[] }>();
const emit = defineEmits<{ toggle: [tag: string] }>();
</script>

<template>
  <div class="flex flex-wrap gap-1">
    <button
      v-for="tag in tags"
      :key="tag"
      type="button"
      class="border px-1.5 py-0.5 font-mono text-[0.625rem] transition-colors hover:border-primary/60"
      :class="
        selected.includes(tag)
          ? 'border-primary/60 bg-primary/15 text-primary'
          : 'border-primary/20 bg-primary/5 text-primary/80'
      "
      :aria-pressed="selected.includes(tag)"
      :title="`Filter by ${tag}`"
      @click="emit('toggle', tag)"
    >
      {{ tag }}
    </button>
  </div>
</template>
