<script setup lang="ts">
import { AdminModeForm, useAdminMode } from "@/shell";
import { ApPageHeader, ApPanel, useNow } from "@/ui";

/**
 * L7 platform admin (ux screens/Admin.md), outside org and mission scope; the 'admin' shell mode
 * draws the top bar and rail. Outside admin mode every route shows the step-up form inline and
 * nothing renders behind it (Auth.md). The session is a boot snapshot, so the live state is lead's.
 * The gate has its own h1, since the routed page (and its header) doesn't mount (a11y S1, lead).
 */
const now = useNow();
const admin = useAdminMode(() => now.value);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <template v-if="!admin.active.value">
      <ApPageHeader label="Platform admin" title="Admin mode" size="reading" />
      <ApPanel index="A0" title="Confirm your password">
        <AdminModeForm />
      </ApPanel>
    </template>
    <RouterView v-else />
  </div>
</template>
