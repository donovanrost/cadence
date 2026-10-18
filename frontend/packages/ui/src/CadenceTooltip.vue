<script setup lang="ts">
import {
  TooltipArrow,
  TooltipContent,
  TooltipPortal,
  TooltipProvider,
  TooltipRoot,
  TooltipTrigger,
} from "reka-ui";

withDefaults(
  defineProps<{
    align?: "start" | "center" | "end";
    content: string;
    side?: "top" | "right" | "bottom" | "left";
  }>(),
  {
    align: "center",
    side: "bottom",
  },
);
</script>

<template>
  <TooltipProvider :delay-duration="250" :skip-delay-duration="100">
    <TooltipRoot>
      <TooltipTrigger as-child><slot /></TooltipTrigger>
      <TooltipPortal>
        <TooltipContent
          class="cadence-tooltip"
          :align="align"
          :collision-padding="12"
          :side="side"
          :side-offset="8"
        >
          {{ content }}
          <TooltipArrow class="cadence-tooltip__arrow" :width="9" :height="5" />
        </TooltipContent>
      </TooltipPortal>
    </TooltipRoot>
  </TooltipProvider>
</template>

<style>
.cadence-tooltip {
  z-index: var(--z-tooltip);
  max-width: 260px;
  padding: 8px 11px;
  border: 1px solid var(--border-default);
  color: var(--color-base-content);
  background: var(--surface-base);
  font-size: var(--type-body-sm);
  line-height: 1.45;
  animation: cadence-tooltip-enter var(--duration-fast) var(--ease-standard);
}

.cadence-tooltip__arrow {
  fill: var(--border-default);
}

@keyframes cadence-tooltip-enter {
  from {
    opacity: 0;
    transform: translateY(-2px);
  }
}
</style>
