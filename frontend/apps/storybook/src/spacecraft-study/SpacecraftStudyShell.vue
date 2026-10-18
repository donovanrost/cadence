<script setup lang="ts">
import { computed, ref } from "vue";
import ApplicationShell from "../../../host/src/shell/ApplicationShell.vue";
import HostPage from "../../../host/src/shell/HostPage.vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import SpacecraftStudy from "./SpacecraftStudy.vue";
import MissionCatalogStudy from "./MissionCatalogStudy.vue";
import { useSpacecraftStudy } from "./state";
import { missionPath, spacecraftPath, useStudyNavigation } from "./navigation";
import type { Scenario } from "./fixtures";

const props = withDefaults(
  defineProps<{ initial?: Scenario; navigation?: "cadence" | "isolated" }>(),
  { initial: "established", navigation: "cadence" },
);
const study = useSpacecraftStudy(props.initial);
const { destination, context, navigate } = useStudyNavigation(study.selectSpacecraft);
const shell = ref<HTMLElement | null>(null);
const breadcrumbs = computed(() => [
  { label: "Flight Operations", href: "/" },
  { label: "Kestrel", href: missionPath },
  ...(destination.value.kind === "spacecraft"
    ? [{ label: "Spacecraft", href: `${missionPath}/spacecraft` }]
    : []),
]);

function navigateStudy(event: MouseEvent) {
  if (
    event.defaultPrevented ||
    event.button !== 0 ||
    event.metaKey ||
    event.ctrlKey ||
    event.shiftKey ||
    event.altKey
  )
    return;
  const anchor = event.target instanceof Element ? event.target.closest("a") : null;
  const href = anchor?.getAttribute("href");
  if (
    !anchor ||
    !href?.startsWith("/") ||
    anchor.target ||
    anchor.hasAttribute("download") ||
    href.startsWith("/iframe.html")
  )
    return;
  event.preventDefault();
  study.inspector.value = null;
  navigate(href);
  const drawer = shell.value?.querySelector<HTMLInputElement>("#sidebar-drawer");
  if (drawer) drawer.checked = false;
}
</script>

<template>
  <main v-if="navigation === 'isolated'"><SpacecraftStudy :study="study" standalone /></main>
  <div v-else ref="shell" class="sc-shell-study" @click="navigateStudy" @submit.prevent>
    <ApplicationShell
      class="sc-shell-frame"
      variant="mission_sidebar"
      :context="context"
      managed-page
    >
      <HostPage
        :key="destination.kind"
        :title="destination.title"
        :breadcrumbs="breadcrumbs"
        workspace
      >
        <SpacecraftStudy v-if="destination.kind === 'spacecraft'" :study="study" />
        <MissionCatalogStudy
          v-else-if="destination.kind === 'catalog'"
          :spacecraft="study.spacecraft"
          :selected="study.selectedId.value"
        />
        <div v-else class="sc-outside-destination">
          <CadencePageHeading
            ><template #title>{{ destination.title }}</template></CadencePageHeading
          ><span class="hero-arrow-top-right-on-square sc-icon-lg" aria-hidden="true" />
          <div>
            <h2>Continue through Cadence</h2>
            <p>
              The shell has taken you to {{ destination.title.toLowerCase() }}. This destination’s
              content is outside the spacecraft design study.
            </p>
            <p>Your spacecraft draft is preserved.</p>
            <CadenceLink :href="spacecraftPath(study.selectedId.value)"
              >Return to {{ study.selectedId.value
              }}<template #icon><span class="hero-arrow-right" /></template
            ></CadenceLink>
          </div>
        </div>
      </HostPage>
    </ApplicationShell>
  </div>
</template>

<style>
.sc-shell-frame {
  height: 100dvh;
}
.sc-shell-study .cd-page--workspace {
  height: 100%;
}
.sc-shell-study .cd-page-body:has(> .spacecraft-study) {
  display: flex;
  padding: 0;
}
.sc-outside-destination {
  display: flex;
  align-items: start;
  gap: 16px;
  max-width: 660px;
  padding-block: 20px;
  font: 13px/1.6 var(--font-sans);
  color: var(--text-subtle);
}
.sc-outside-destination h2 {
  margin: 0 0 8px;
  font-size: 18px;
  font-weight: 600;
  color: var(--text-bright);
}
.sc-outside-destination p {
  margin: 0 0 16px;
}
</style>
