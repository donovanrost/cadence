<script setup lang="ts">
import type { FrontendSession } from "../auth/auth-client";
import AdminNavbar from "./AdminNavbar.vue";

defineProps<{
  activeRoute: string;
  session: FrontendSession;
}>();

const emit = defineEmits<{
  navigate: [path: string];
  signOut: [];
}>();

const navigation = [
  { index: "01", label: "Overview", path: "/admin" },
  { index: "02", label: "Organizations", path: "/admin/organizations" },
  { index: "03", label: "Runtime", path: "/admin/runtime" },
  { index: "04", label: "Applications", path: "/applications" },
] as const;
</script>

<template>
  <div id="admin-shell" class="admin-shell">
    <AdminNavbar
      class="admin-shell__navbar"
      :session="session"
      @navigate="emit('navigate', $event)"
      @sign-out="emit('signOut')"
    />

    <aside class="admin-rail" aria-label="System administration">
      <div class="admin-rail__label">CONTROL PLANE</div>
      <nav id="admin-navigation">
        <button
          v-for="item in navigation"
          :id="`admin-nav-${item.index}`"
          :key="item.path"
          type="button"
          :class="{ active: activeRoute === item.path }"
          :aria-current="activeRoute === item.path ? 'page' : undefined"
          @click="emit('navigate', item.path)"
        >
          <span>{{ item.index }}</span>
          <strong>{{ item.label }}</strong>
          <i aria-hidden="true">→</i>
        </button>
      </nav>

      <div class="admin-rail__foot">
        <span>FRONTEND</span>
        <strong>VUE 3 / POC</strong>
      </div>
    </aside>

    <main id="admin-workspace" class="admin-workspace">
      <slot />
    </main>
  </div>
</template>

<style scoped>
.admin-shell {
  min-height: 100vh;
  display: grid;
  grid-template:
    "topbar topbar" 56px
    "rail workspace" minmax(0, 1fr) /
    232px minmax(0, 1fr);
  color: var(--cadence-color-text);
  background: var(--cadence-color-canvas);
}

.admin-shell__navbar {
  grid-area: topbar;
}

.admin-rail__label,
.admin-rail__foot {
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-label);
  letter-spacing: var(--cadence-tracking-label);
  text-transform: uppercase;
}

.admin-rail__label {
  color: var(--cadence-color-text-muted);
}

.admin-rail {
  grid-area: rail;
  display: grid;
  grid-template-rows: auto 1fr auto;
  border-right: 1px solid var(--cadence-color-border);
  background: var(--cadence-color-shell);
}

.admin-rail__label {
  padding: var(--cadence-space-4) var(--cadence-space-5);
  border-bottom: 1px solid var(--cadence-color-border-subtle);
}

.admin-rail nav {
  display: flex;
  flex-direction: column;
}

.admin-rail nav button {
  display: grid;
  grid-template-columns: 28px 1fr auto;
  gap: var(--cadence-space-2);
  align-items: center;
  min-height: 48px;
  padding: 0 var(--cadence-space-4);
  border: 0;
  border-bottom: 1px solid var(--cadence-color-border-subtle);
  color: var(--cadence-color-text-secondary);
  background: transparent;
  text-align: left;
  cursor: pointer;
}

.admin-rail nav button span,
.admin-rail nav button i {
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-label);
  font-style: normal;
}

.admin-rail nav button i {
  opacity: 0;
}

.admin-rail nav button strong {
  font-size: 0.78rem;
  letter-spacing: 0.02em;
}

.admin-rail nav button:hover,
.admin-rail nav button.active {
  color: var(--cadence-color-text-strong);
  background: var(--cadence-color-surface-inset);
}

.admin-rail nav button.active {
  box-shadow: inset 3px 0 var(--cadence-color-signal);
}

.admin-rail nav button.active span,
.admin-rail nav button.active i {
  color: var(--cadence-color-signal);
  opacity: 1;
}

.admin-rail__foot {
  display: grid;
  gap: var(--cadence-space-1);
  padding: var(--cadence-space-4) var(--cadence-space-5);
  border-top: 1px solid var(--cadence-color-border);
  color: var(--cadence-color-text-muted);
}

.admin-rail__foot strong {
  color: var(--cadence-color-text-secondary);
}

.admin-workspace {
  grid-area: workspace;
  min-width: 0;
  overflow: auto;
}

@media (max-width: 900px) {
  .admin-shell {
    grid-template:
      "topbar" auto
      "rail" auto
      "workspace" 1fr /
      minmax(0, 1fr);
  }

  .admin-rail {
    grid-template-columns: auto 1fr;
    grid-template-rows: auto;
    border-right: 0;
    border-bottom: 1px solid var(--cadence-color-border);
  }

  .admin-rail nav {
    flex-direction: row;
    overflow-x: auto;
  }

  .admin-rail nav button {
    min-width: 150px;
    border-right: 1px solid var(--cadence-color-border-subtle);
    border-bottom: 0;
  }

  .admin-rail__foot {
    display: none;
  }
}

@media (max-width: 620px) {
  .admin-rail__label {
    display: none;
  }
}
</style>
