<script setup lang="ts">
import AuthLayoutBrand from "./AuthLayoutBrand.vue";
import {
  PrimaryNavigation as ShellNavigation,
  AccountMenu as ShellAccount,
  navigateAttrs,
} from "../auth-and-navigation";
import OpsWorkspaceFrame from "../ops-workspace/features/frame/OpsWorkspaceFrame.vue";
defineProps<{
  managedPage?: boolean;
  variant: "auth" | "ops" | "sidebar" | "mission_sidebar" | "user_shell";
  context: unknown;
}>();
</script>
<template>
  <div
    v-if="variant === 'auth'"
    class="min-h-screen flex flex-col items-center justify-center px-4 py-12"
  >
    <div class="w-full max-w-sm space-y-6">
      <AuthLayoutBrand class="text-center" />
      <div id="application-content" class="contents"><slot /></div>
    </div>
  </div>
  <OpsWorkspaceFrame v-else-if="variant === 'ops'" :context="context"><slot /></OpsWorkspaceFrame>
  <div
    v-else-if="variant === 'sidebar' || variant === 'mission_sidebar'"
    class="drawer lg:drawer-open"
  >
    <input
      id="sidebar-drawer"
      type="checkbox"
      class="drawer-toggle"
      aria-label="Navigation drawer"
    />
    <div class="drawer-content flex flex-col">
      <header class="lg:hidden flex items-center justify-between p-4 border-b border-base-300">
        <label for="sidebar-drawer" aria-label="Open navigation" class="btn btn-ghost btn-sm"
          ><span class="hero-bars-3 h-5 w-5"></span></label
        ><span class="flex-1 text-center font-semibold text-sm tracking-wider uppercase"
          >Cadence</span
        ><ShellAccount id="account-mobile" :context="context" />
      </header>
      <header
        class="hidden lg:flex items-center justify-end gap-3 px-4 h-10 border-b border-primary/20 bg-base-200 hud-grid shrink-0"
      >
        <ShellAccount id="account-desktop" :context="context" />
      </header>
      <main class="flex-1 overflow-y-auto bg-base-100">
        <div :class="managedPage ? 'contents' : 'p-6'">
          <div id="application-content" class="contents"><slot /></div>
        </div>
      </main>
    </div>
    <div class="drawer-side">
      <ShellNavigation :context="context" :mission="variant === 'mission_sidebar'">
        <template #footer><slot name="navigation-footer" /></template>
      </ShellNavigation>
    </div>
  </div>
  <div v-else class="min-h-screen flex flex-col bg-base-100">
    <header
      class="flex items-center justify-between px-4 h-12 border-b border-primary/20 bg-base-200 hud-grid"
    >
      <a v-bind="navigateAttrs('/')" class="flex items-center gap-2 text-primary"
        ><span>◆</span><span class="text-xs font-bold tracking-[0.15em]">CADENCE</span></a
      ><ShellAccount id="account-user" :context="context" />
    </header>
    <main class="flex-1 overflow-y-auto" :class="!managedPage && 'p-6'">
      <div id="application-content" class="contents"><slot /></div>
    </main>
  </div>
</template>
