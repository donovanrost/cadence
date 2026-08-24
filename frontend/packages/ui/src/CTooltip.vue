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
          class="cui-tooltip"
          :align="align"
          :collision-padding="12"
          :side="side"
          :side-offset="8"
        >
          {{ content }}
          <TooltipArrow class="cui-tooltip__arrow" :width="9" :height="5" />
        </TooltipContent>
      </TooltipPortal>
    </TooltipRoot>
  </TooltipProvider>
</template>

<style>
.cui-tooltip {
  z-index: var(--cadence-layer-tooltip);
  max-width: 260px;
  padding: 8px 11px;
  border: 1px solid var(--cadence-color-border);
  color: var(--cadence-color-text);
  background: var(--cadence-color-canvas);
  font-size: var(--cadence-type-body-sm);
  line-height: 1.45;
  animation: cui-tooltip-enter var(--cadence-duration-fast) var(--cadence-ease-standard);
}

.cui-tooltip__arrow {
  fill: var(--cadence-color-border);
}

@keyframes cui-tooltip-enter {
  from {
    opacity: 0;
    transform: translateY(-2px);
  }
}
</style>
