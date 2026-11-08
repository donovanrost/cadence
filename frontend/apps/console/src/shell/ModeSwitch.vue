<script setup lang="ts">
import type { ShellMode } from "@/router/meta.ts";

defineProps<{ mode: ShellMode; org: string; mission: string }>();
</script>

<template>
  <div class="flex items-center border-r border-hairline px-[18px]">
    <nav aria-label="Mode" class="flex items-center border border-line">
      <RouterLink
        v-for="item in [
          { key: 'ops', label: 'Ops', to: 'ops.now' },
          { key: 'setup', label: 'Setup', to: 'setup.readiness' },
        ] as const"
        :key="item.key"
        :to="{ name: item.to, params: { org, mission } }"
        :aria-current="mode === item.key ? 'page' : undefined"
        class="flex h-[30px] items-center px-3 font-display text-md font-semibold tracking-title uppercase no-underline"
        :class="
          mode === item.key
            ? 'bg-action text-on-action hover:text-on-action'
            : 'text-text-3 hover:text-readout'
        "
        >{{ item.label }}</RouterLink
      >
    </nav>
  </div>
</template>
