<script setup lang="ts">
import type { FederatedApplicationProps } from "@cadence/plugin-sdk";
import { CButton, CStatePanel, CStatus } from "@cadence/ui";
import { computed } from "vue";
import { pageSurfaces } from "./federated-application";

const props = defineProps<FederatedApplicationProps>();

const activeSurface = computed(() => {
  const requested = new URL(window.location.href).searchParams.get("surface");
  return pageSurfaces.find((surface) => surface.surfaceId === requested) ?? pageSurfaces[0];
});

function openSurface(surfaceId: string): void {
  const url = new URL(window.location.href);
  url.searchParams.set("surface", surfaceId);
  window.history.replaceState({}, "", url);
  window.dispatchEvent(new PopStateEvent("popstate"));
}
</script>

<template>
  <section id="mission-catalog-application" class="mission-catalog-application">
    <header class="mission-catalog-application__header">
      <div>
        <p class="mission-catalog-eyebrow">FIRST-PARTY DOMAIN REMOTE</p>
        <h1>Mission &amp; Catalog</h1>
        <p>Organization identity, mission setup, and immutable catalog provenance.</p>
      </div>
      <CStatus :tone="props.context ? 'nominal' : 'warning'" pulse>
        {{ props.context ? "PHOENIX CONTEXT" : "CONTEXT CHECK" }}
      </CStatus>
    </header>

    <nav class="mission-catalog-surface-nav" aria-label="Mission and catalog surfaces">
      <button
        v-for="surface in pageSurfaces"
        :id="`mission-catalog-surface-${surface.surfaceId}`"
        :key="surface.surfaceId"
        type="button"
        :class="{ 'is-active': activeSurface?.surfaceId === surface.surfaceId }"
        @click="openSurface(surface.surfaceId)"
      >
        <span>{{ String(surface.navigation.order).padStart(2, "0") }}</span>
        {{ surface.navigation.label }}
      </button>
    </nav>

    <CStatePanel
      id="mission-catalog-composition-pending"
      title="Surface selected"
      :description="`${activeSurface?.navigation.label ?? 'Mission'} is ready for Phoenix-owned presentation data. The route composition layer will mount the named surface component.`"
      tone="neutral"
    >
      <template #action>
        <CButton id="mission-catalog-context-check" size="sm" @click="props.bridge.subscribe(() => undefined)">
          Verify host bridge
        </CButton>
      </template>
    </CStatePanel>
  </section>
</template>
