<script setup lang="ts">
import type { OpState } from "./status.ts";

/** Decorative state shape. The adjacent word (or an aria-label on the owner) carries meaning. */
defineProps<{ state: OpState }>();
</script>

<template>
  <span aria-hidden="true" class="ap-mark" :class="`ap-mark--${state}`" />
</template>

<style scoped>
.ap-mark {
  display: inline-block;
  flex: none;
  box-sizing: border-box;
  width: 8px;
  height: 8px;
}
.ap-mark--nominal {
  background: var(--color-nominal);
}
.ap-mark--caution {
  width: 10px;
  height: 9px;
  background: var(--color-caution);
  clip-path: polygon(50% 0, 100% 100%, 0 100%);
}
.ap-mark--crit {
  background: var(--color-crit);
  transform: rotate(45deg);
}
.ap-mark--stale {
  border: 1px solid var(--color-stale);
  background-image: var(--apogee-hatch-stale);
}
.ap-mark--off {
  border: 1px dashed var(--color-off);
}
.ap-mark--live {
  background: var(--color-readout);
}
.ap-mark--neutral {
  background: var(--color-text-4);
}
.ap-mark--optional {
  width: 10px;
  height: 2px;
  background: var(--color-text-4);
}
</style>
