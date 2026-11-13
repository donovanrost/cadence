<script setup lang="ts">
import { formatClock, useNow } from "@/ui";

/**
 * Auth layout (ux Auth.md): a centred 400px column (16px gutters on a phone), the Cadence mark, one
 * panel per screen, no rail or top bar, and a UTC clock in the footer. Public routes render here,
 * outside SessionProvider and AppShell.
 */
const now = useNow();
</script>

<template>
  <!-- Transparent: the body paints the grid over vacuum (apogee.css --apogee-grid). -->
  <div class="flex min-h-screen flex-col items-center px-4 py-10">
    <main id="main" class="flex w-full max-w-[400px] flex-1 flex-col justify-center gap-6">
      <p class="ap-label m-0 text-center">Cadence</p>
      <div class="flex flex-col gap-4 border border-hairline bg-panel p-6">
        <slot />
      </div>
    </main>
    <footer class="pt-6 font-mono text-xs text-text-3">UTC {{ formatClock(now) }}</footer>
  </div>
</template>
