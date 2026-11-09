<script setup lang="ts">
/** Mono chip. `name` renders a key in text-4 before the value; `removable` adds a labelled × button. */
defineProps<{ name?: string | undefined; removable?: boolean | undefined; removeLabel?: string }>();
defineEmits<{ remove: [] }>();
</script>

<template>
  <span
    class="inline-flex h-7 items-center gap-1.5 border border-line bg-raised pl-2.5 font-mono text-sm text-readout"
    :class="removable ? 'pr-0.5' : 'pr-2.5'"
  >
    <span v-if="name" class="text-text-4">{{ name }}</span>
    <slot />
    <button
      v-if="removable"
      type="button"
      class="inline-flex size-[22px] cursor-pointer max-md:hit-44 items-center justify-center border-0 bg-transparent text-text-3 hover:text-readout"
      :aria-label="removeLabel ?? 'Remove'"
      @click="$emit('remove')"
    >
      ×
    </button>
  </span>
</template>
