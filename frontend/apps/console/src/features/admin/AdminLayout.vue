<script setup lang="ts">
import { AdminModeForm, useAdminMode } from "@/shell";
import { ApPanel, useNow } from "@/ui";

/**
 * L7 platform admin (ux screens/Admin.md), outside org and mission scope; the 'admin' shell mode
 * draws the top bar and rail. Outside admin mode every route shows the step-up form inline and
 * nothing renders behind it (Auth.md). The session is a boot snapshot, so the live state is lead's.
 */
const now = useNow();
const admin = useAdminMode(() => now.value);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPanel v-if="!admin.active.value" index="A0" title="Admin mode">
      <AdminModeForm />
    </ApPanel>
    <RouterView v-else />
  </div>
</template>
