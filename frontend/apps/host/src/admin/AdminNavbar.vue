<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from "vue";
import { CButton } from "@cadence/ui";
import type { FrontendSession } from "../auth/auth-client";

defineProps<{
  session: FrontendSession;
}>();

const emit = defineEmits<{
  navigate: [path: string];
  signOut: [];
}>();

const accountMenuOpen = ref(false);
const accountMenuRoot = ref<HTMLElement>();
const accountMenuTrigger = ref<HTMLButtonElement>();

function initials(displayName: string): string {
  return displayName
    .split(" ")
    .map((part) => part[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();
}

function closeAccountMenu(): void {
  accountMenuOpen.value = false;
}

function signOut(): void {
  closeAccountMenu();
  emit("signOut");
}

function handleDocumentPointerDown(event: PointerEvent): void {
  if (event.target instanceof Node && !accountMenuRoot.value?.contains(event.target)) {
    closeAccountMenu();
  }
}

function handleDocumentKeydown(event: KeyboardEvent): void {
  if (event.key !== "Escape" || !accountMenuOpen.value) return;

  closeAccountMenu();
  accountMenuTrigger.value?.focus();
}

onMounted(() => {
  document.addEventListener("pointerdown", handleDocumentPointerDown);
  document.addEventListener("keydown", handleDocumentKeydown);
});

onBeforeUnmount(() => {
  document.removeEventListener("pointerdown", handleDocumentPointerDown);
  document.removeEventListener("keydown", handleDocumentKeydown);
});
</script>

<template>
  <header id="admin-navbar" class="admin-navbar">
    <button
      id="admin-home"
      class="admin-navbar__wordmark"
      type="button"
      aria-label="Cadence administration home"
      @click="emit('navigate', '/admin')"
    >
      CADENCE
    </button>

    <div ref="accountMenuRoot" class="admin-navbar__identity">
      <button
        id="admin-account-menu-trigger"
        ref="accountMenuTrigger"
        class="admin-navbar__account-trigger"
        type="button"
        :aria-expanded="accountMenuOpen"
        aria-controls="admin-account-menu"
        :aria-label="`Open account menu for ${session.actor.displayName}`"
        @click="accountMenuOpen = !accountMenuOpen"
      >
        <span class="admin-navbar__initials" aria-hidden="true">
          {{ initials(session.actor.displayName) }}
        </span>
        <span class="admin-navbar__person" aria-hidden="true">
          <strong>{{ session.actor.displayName }}</strong>
          <small>Platform admin</small>
        </span>
        <svg class="admin-navbar__chevron" viewBox="0 0 16 16" aria-hidden="true">
          <path d="m4 6 4 4 4-4" />
        </svg>
      </button>

      <Transition name="account-menu">
        <div
          v-if="accountMenuOpen"
          id="admin-account-menu"
          class="admin-navbar__menu"
          role="group"
          aria-label="Account actions"
        >
          <div class="admin-navbar__menu-context">
            <span>Signed in as</span>
            <strong>{{ session.actor.email }}</strong>
          </div>
          <CButton
            id="admin-sign-out"
            class="admin-navbar__sign-out"
            size="sm"
            variant="quiet"
            @click="signOut"
          >
            <span>Sign out</span>
            <span aria-hidden="true">→</span>
          </CButton>
        </div>
      </Transition>
    </div>
  </header>
</template>

<style scoped>
.admin-navbar {
  display: grid;
  grid-template-columns: 232px minmax(0, 1fr);
  height: 56px;
  border-bottom: 1px solid var(--cadence-color-border);
  color: var(--cadence-color-text);
  background: var(--cadence-color-shell);
}

.admin-navbar__wordmark {
  padding: 0 var(--cadence-space-5);
  border: 0;
  border-right: 1px solid var(--cadence-color-border);
  color: var(--cadence-color-text-strong);
  background: transparent;
  font-size: 0.8125rem;
  font-weight: 720;
  letter-spacing: 0.16em;
  text-align: left;
  cursor: pointer;
}

.admin-navbar__identity {
  position: relative;
  justify-self: end;
  border-left: 1px solid var(--cadence-color-border);
}

.admin-navbar__account-trigger {
  display: flex;
  height: 55px;
  align-items: center;
  gap: var(--cadence-space-3);
  padding: 0 var(--cadence-space-4);
  border: 0;
  color: inherit;
  background: transparent;
  text-align: left;
  cursor: pointer;
  transition: background var(--cadence-transition-fast);
}

.admin-navbar__account-trigger:hover,
.admin-navbar__account-trigger[aria-expanded="true"] {
  background: var(--cadence-color-surface-inset);
}

.admin-navbar__account-trigger:focus-visible {
  outline: 1px solid var(--cadence-color-signal);
  outline-offset: -2px;
}

.admin-navbar__initials {
  display: grid;
  width: 28px;
  height: 28px;
  place-items: center;
  border: 1px solid var(--cadence-color-border);
  font-family: var(--cadence-font-mono);
  font-size: 0.625rem;
}

.admin-navbar__person {
  display: grid;
  gap: 1px;
  min-width: 0;
}

.admin-navbar__person strong {
  overflow: hidden;
  color: var(--cadence-color-text-strong);
  font-size: 0.75rem;
  font-weight: 620;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.admin-navbar__person small {
  color: var(--cadence-color-text-muted);
  font-size: 0.6875rem;
}

.admin-navbar__chevron {
  width: 14px;
  height: 14px;
  color: var(--cadence-color-text-muted);
  fill: none;
  stroke: currentColor;
  stroke-linecap: square;
  stroke-linejoin: miter;
  stroke-width: 1.5;
  transition: transform var(--cadence-transition-fast);
}

.admin-navbar__account-trigger[aria-expanded="true"] .admin-navbar__chevron {
  color: var(--cadence-color-signal);
  transform: rotate(180deg);
}

.admin-navbar__menu {
  position: absolute;
  z-index: 20;
  top: calc(100% + 1px);
  right: var(--cadence-space-3);
  display: grid;
  width: 232px;
  border: 1px solid var(--cadence-color-border-strong);
  color: var(--cadence-color-text);
  background: var(--cadence-color-surface-raised);
  box-shadow: var(--cadence-shadow-floating);
}

.admin-navbar__menu::before {
  position: absolute;
  top: -1px;
  right: -1px;
  left: -1px;
  height: 2px;
  background: var(--cadence-color-signal);
  content: "";
}

.admin-navbar__menu-context {
  display: grid;
  gap: var(--cadence-space-1);
  padding: var(--cadence-space-3) var(--cadence-space-4);
  border-bottom: 1px solid var(--cadence-color-border-subtle);
}

.admin-navbar__menu-context span {
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-label);
  letter-spacing: var(--cadence-tracking-label);
  text-transform: uppercase;
}

.admin-navbar__menu-context strong {
  overflow: hidden;
  color: var(--cadence-color-text-strong);
  font-size: 0.75rem;
  font-weight: 620;
  text-overflow: ellipsis;
  white-space: nowrap;
}

:deep(.admin-navbar__sign-out) {
  justify-content: space-between;
  min-height: 40px;
  padding: 0 var(--cadence-space-4);
  border: 0;
  text-align: left;
}

.account-menu-enter-active,
.account-menu-leave-active {
  transition:
    opacity var(--cadence-transition-fast),
    transform var(--cadence-transition-fast);
  transform-origin: top right;
}

.account-menu-enter-from,
.account-menu-leave-to {
  opacity: 0;
  transform: translateY(-4px);
}

@media (max-width: 760px) {
  .admin-navbar {
    grid-template-columns: 160px 1fr;
  }

  .admin-navbar__identity {
    justify-self: end;
  }
}

@media (max-width: 520px) {
  .admin-navbar {
    grid-template-columns: 132px 1fr;
  }

  .admin-navbar__wordmark {
    padding: 0 var(--cadence-space-4);
  }

  .admin-navbar__person {
    display: none;
  }

  .admin-navbar__account-trigger {
    gap: var(--cadence-space-2);
    padding: 0 var(--cadence-space-3);
  }

  .admin-navbar__menu {
    right: var(--cadence-space-2);
  }
}
</style>
