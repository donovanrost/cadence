<script setup lang="ts">
import { computed, ref, useId } from "vue";
import { useRoute } from "vue-router";
import { useDisclosure } from "./disclosure.ts";
import type { ConsoleScope } from "./scope.ts";
import { TopBarLevel, useTopBarLevel } from "./topbar-fit.ts";

const level = useTopBarLevel();

const props = defineProps<{ scope: ConsoleScope }>();
const route = useRoute();
const root = ref<HTMLElement | null>(null);
const { open, toggle, close } = useDisclosure(root);
const listLabel = useId();
/**
 * A disclosure, not a menu (ux, a11y-checklist B3): navigation links Tab in order. When focus moves
 * to something outside (a Tab past the last mission), the list closes instead of staying over the page.
 */
function onFocusOut(event: FocusEvent) {
  const next = event.relatedTarget;
  if (open.value && next instanceof Node && root.value && !root.value.contains(next)) close();
}

const organization = computed(() =>
  props.scope.kind === "organization" ||
  props.scope.kind === "mission" ||
  props.scope.kind === "unknown-mission"
    ? props.scope.organization
    : null,
);
const missionName = computed(() =>
  props.scope.kind === "mission" ? props.scope.mission.name : null,
);
const currentSlug = computed(() =>
  props.scope.kind === "mission" ? props.scope.mission.slug : null,
);
/** Switching mission keeps the mode: Setup goes to the other mission's Readiness. */
const targetName = computed(() =>
  route.meta.mode === "setup" || route.meta.mode === "takeover" ? "setup.readiness" : "ops.now",
);
</script>

<template>
  <div
    v-if="organization"
    ref="root"
    class="relative flex border-r border-hairline"
    @focusout="onFocusOut"
  >
    <button
      type="button"
      class="flex cursor-pointer items-center gap-2.5 border-0 bg-transparent min-w-0 px-4 md:px-[18px] font-display text-base font-semibold tracking-tag text-readout uppercase hover:bg-raised"
      :aria-expanded="open"
      aria-controls="mission-switcher"
      @click="toggle"
    >
      <!-- At its give-way step the org name leaves the eye, not the accessible name (ux IA §Top bar). -->
      <span
        class="text-text-4 max-md:sr-only"
        :class="level >= TopBarLevel.crumbMission ? 'sr-only' : ''"
        >{{ organization.name }} /</span
      >
      <span>{{ missionName ?? "Choose mission" }}</span>
      <svg
        width="10"
        height="10"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="3"
        class="text-text-4"
        aria-hidden="true"
      >
        <path d="m6 9 6 6 6-6" />
      </svg>
    </button>
    <div
      v-if="open"
      id="mission-switcher"
      class="absolute top-full left-0 z-30 min-w-[280px] border border-line bg-raised py-1.5"
    >
      <p :id="listLabel" class="ap-label px-3.5 pt-1.5 pb-1">Missions in {{ organization.name }}</p>
      <ul class="m-0 list-none p-0" :aria-labelledby="listLabel">
        <li v-for="mission in organization.missions" :key="mission.id">
          <RouterLink
            :to="{ name: targetName, params: { org: organization.slug, mission: mission.slug } }"
            class="flex h-10 items-center gap-2.5 px-3.5 text-base no-underline hover:bg-raised-hi"
            :class="
              mission.slug === currentSlug ? 'shadow-[inset_2px_0_0_var(--color-readout)]' : ''
            "
            :aria-current="mission.slug === currentSlug ? 'true' : undefined"
            @click="close"
            >{{ mission.name }}</RouterLink
          >
        </li>
      </ul>
      <p v-if="organization.missions.length === 0" class="m-0 px-3.5 py-2 text-md text-text-3">
        No missions you can open in this organization.
      </p>
    </div>
  </div>
</template>
