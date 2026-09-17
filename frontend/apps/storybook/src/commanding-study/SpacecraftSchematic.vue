<script setup lang="ts">
defineProps<{ selected?: boolean }>();
</script>
<template>
  <svg
    class="study-spacecraft"
    :class="{ 'is-selected': selected }"
    viewBox="0 0 160 80"
    fill="none"
    aria-hidden="true"
  >
    <g stroke="currentColor" stroke-width="1.2" stroke-linejoin="round">
      <path
        d="M10 32 43 21 58 44 25 56z M102 32 135 21 150 44 117 56z"
        class="study-spacecraft__panel"
      />
      <path
        d="m21 28 15 24m-4-27 15 23m-31-8 33-10m63-1 15 23m-4-27 15 23m-31-8 33-10"
        opacity=".45"
      />
      <path
        d="m60 27 20-9 20 13-20 9z M60 27v28l20 12V40m20-9v26L80 67"
        class="study-spacecraft__body"
      />
      <path d="m44 36 16 5m40 2 14-4M80 18V8m-5 0h10M68 42v9l6 4v-9z" />
      <circle cx="89" cy="48" r="3" />
    </g>
  </svg>
</template>
