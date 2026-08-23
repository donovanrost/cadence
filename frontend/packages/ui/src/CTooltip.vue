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
  z-index: 100;
  max-width: 240px;
  padding: 7px 9px;
  border: 1px solid var(--cadence-color-border-strong);
  color: var(--cadence-color-text);
  background: var(--cadence-color-surface-raised);
  box-shadow: 0 10px 30px rgb(0 0 0 / 32%);
  font-family: var(--cadence-font-mono);
  font-size: 9px;
  letter-spacing: 0.035em;
  animation: cui-tooltip-enter 100ms ease-out;
}

.cui-tooltip__arrow {
  fill: var(--cadence-color-border-strong);
}

@keyframes cui-tooltip-enter {
  from {
    opacity: 0;
    transform: translateY(-2px);
  }
}
</style>
