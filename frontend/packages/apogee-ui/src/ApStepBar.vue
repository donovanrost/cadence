<script setup lang="ts">
/** Wizard / flow progress. `current` is the index of the active step. */
defineProps<{ steps: readonly string[]; current: number; label: string }>();
</script>

<template>
  <nav :aria-label="label">
    <ol class="m-0 flex list-none items-stretch border border-hairline p-0">
      <li
        v-for="(step, i) in steps"
        :key="step"
        :aria-current="i === current ? 'step' : undefined"
        class="flex h-11 flex-1 items-center gap-2.5 whitespace-nowrap max-md:flex-none border-r border-hairline px-4 font-display text-md font-semibold tracking-tag uppercase last:border-r-0"
        :class="
          i === current
            ? 'bg-raised text-readout shadow-[inset_0_-2px_0_var(--color-readout)]'
            : i < current
              ? 'text-text-3'
              : 'text-text-4'
        "
      >
        <span class="font-mono text-xs" aria-hidden="true">{{
          i < current
            ? "✓"
            : i === current
              ? `● ${String(i + 1).padStart(2, "0")}`
              : String(i + 1).padStart(2, "0")
        }}</span>
        <span>{{ step }}<span v-if="i < current" class="sr-only"> (done)</span></span>
      </li>
    </ol>
  </nav>
</template>
