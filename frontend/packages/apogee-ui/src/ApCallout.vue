<script setup lang="ts">
import ApStatusMark from "./ApStatusMark.vue";

/**
 * Inline contextual sentence: wash + mark + one sentence + optional trailing action.
 * `role` (a11y B6, #243): the role follows what happened, not the tone. A caution-toned refusal or
 * failure of the person's own act passes `role="alert"`; without it, crit is alert, the rest status
 * (standing cautions keep that default).
 */
defineProps<{
  tone: "nominal" | "caution" | "crit" | "stale" | "off" | "info";
  role?: "alert" | "status" | undefined;
}>();
</script>

<template>
  <div
    :role="role ?? (tone === 'crit' ? 'alert' : 'status')"
    class="flex items-center gap-3 px-4 py-2.5 text-base text-readout"
    :class="{
      'bg-[var(--apogee-wash-crit)]': tone === 'crit',
      'bg-[var(--apogee-wash-caution)]': tone === 'caution',
      'bg-[rgba(47,208,138,0.06)]': tone === 'nominal',
      'bg-[rgba(164,151,255,0.08)]': tone === 'stale',
      'bg-raised': tone === 'info' || tone === 'off',
    }"
  >
    <!-- The mark sits on the first line (1lh), not the middle of a long body (qa U30 #2). -->
    <span class="flex min-w-0 flex-1 gap-3">
      <span v-if="tone !== 'info'" class="flex h-[1lh] flex-none items-center"
        ><ApStatusMark :state="tone"
      /></span>
      <span class="min-w-0 flex-1"><slot /></span>
    </span>
    <slot name="action" />
  </div>
</template>
