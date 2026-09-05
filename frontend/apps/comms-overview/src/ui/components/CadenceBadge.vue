<script setup lang="ts">
type Tone = "info" | "success" | "warning" | "error"

const props = defineProps<{tone: Tone}>()

const toneClasses: Record<Tone, string> = {
  info: "bg-info/20 text-info",
  success: "bg-success/20 text-success",
  warning: "bg-warning/20 text-warning",
  error: "bg-error/20 text-error"
}
</script>

<template>
  <span
    class="inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide"
    :class="toneClasses[props.tone]"
  ><slot /></span>
</template>
