<script setup lang="ts">
import { ref } from "vue";
import { ApMenuButton, ApMenuItem, ApPanel } from "@/ui";

/** Development-only review of ApMenuButton / ApMenuItem (design-language §6) with fixture items. */
const last = ref("Nothing chosen yet.");
</script>

<template>
  <ApPanel index="K6" title="ApMenuButton" meta="FIXTURE ITEMS · KEYBOARD: ↓ ↑ HOME END ESC TAB">
    <div class="flex items-center gap-6">
      <ApMenuButton label="More section actions">
        <ApMenuItem disabled="It's already first.">Move up</ApMenuItem>
        <ApMenuItem @select="last = 'Move down'">Move down</ApMenuItem>
        <ApMenuItem @select="last = 'Remove section…'">Remove section…</ApMenuItem>
      </ApMenuButton>
      <ApMenuButton
        label="FX, account menu for Fixture Operator"
        menu-label="Account menu for Fixture Operator"
        trigger-class="h-10 w-[52px] cursor-pointer border border-line bg-transparent font-display text-base font-semibold tracking-[.1em] text-readout hover:bg-raised"
        menu-class="min-w-[260px]"
        align="start"
      >
        <template #trigger>FX</template>
        <div role="none" class="px-3.5 pt-1.5 pb-2.5">
          <p class="m-0 text-base font-semibold">Fixture Operator</p>
          <p class="m-0 font-mono text-xs text-text-3">operator@example.invalid</p>
        </div>
        <ApMenuItem :to="{ name: 'kit' }">This page (a link item)</ApMenuItem>
        <p role="none" class="ap-label px-3.5 pt-3 pb-1">Group label</p>
        <ApMenuItem @select="last = 'Grouped action'">Grouped action</ApMenuItem>
      </ApMenuButton>
      <p class="m-0 text-sm text-text-3" aria-live="polite">{{ last }}</p>
    </div>
  </ApPanel>
</template>
