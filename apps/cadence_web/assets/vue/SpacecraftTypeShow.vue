<script setup lang="ts">
import CadenceCard from "./ui/components/CadenceCard.vue"
import CadenceDataRow from "./ui/components/CadenceDataRow.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import CadenceTableFrame from "./ui/components/CadenceTableFrame.vue"
type NavigationItem = {
  label: string
  href: string
}

type Navigation = {
  mission: NavigationItem
  spacecraft: NavigationItem
  profiles: NavigationItem
  current: {label: string}
}

type DetailItem = {
  id: string
  label: string
  value: string
}

type Application = {
  id: string
  label: string
}

type SpacecraftProfile = {
  id: string
  profile_id: string
  display_name: string
  version: string
  lifecycle: string
  downlink_protocol: string
  uplink_protocol: string
  packet_protocol: string
  frame_parameters: DetailItem[]
  applications: Application[]
}

type Labels = {
  byte_interpretation: string
  applications: string
  version_history: string
  frame_parameters: string
  no_applications: string
  downlink_protocol: string
  uplink_protocol: string
  packet_protocol: string
  lifecycle: string
  version: string
  downlink: string
  uplink: string
}

type Version = {
  id: string
  version: string
  lifecycle: string
  downlink_protocol: string
  uplink_protocol: string
}

defineProps<{
  profile: SpacecraftProfile
  navigation: Navigation
  labels: Labels
  versions: Version[]
}>()
</script>

<template>
  <div id="spacecraft-profile-show-surface" class="space-y-6">
    <CadencePageHeaderFrame variant="compact">
      <div>
        <nav
          aria-label="Breadcrumb"
          class="flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
        >
          <a
            :href="navigation.mission.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="hover:text-primary transition-colors"
          >{{ navigation.mission.label }}</a>
          <span class="text-base-content/20" aria-hidden="true">/</span>
          <a
            :href="navigation.spacecraft.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="hover:text-primary transition-colors"
          >{{ navigation.spacecraft.label }}</a>
          <span class="text-base-content/20" aria-hidden="true">/</span>
          <a
            :href="navigation.profiles.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="hover:text-primary transition-colors"
          >{{ navigation.profiles.label }}</a>
          <span class="text-base-content/20" aria-hidden="true">/</span>
          <span class="text-primary/90">{{ navigation.current.label }}</span>
        </nav>

        <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
          {{ profile.display_name }}
          <span class="ml-3 font-mono text-base text-base-content/60">
            <span class="mc-value-medium text-base-content">{{ profile.version }}</span>
            <span class="hud-label">{{ profile.lifecycle }}</span>
          </span>
        </h1>
      </div>
    </CadencePageHeaderFrame>

    <CadenceCard
      id="spacecraft-profile-byte-interpretation"
      class="card bg-base-200 border border-base-300"
      body-class="card-body p-6"
    >
        <p class="hud-label">{{ labels.byte_interpretation }}</p>
        <div class="mt-5 grid gap-x-8 gap-y-2 md:grid-cols-2">
          <CadenceDataRow
            row-class="hud-data-row"
            label-class="hud-data-label"
            :label="labels.downlink_protocol"
          >
            <span class="hud-data-value">
              <span class="uppercase">{{ profile.downlink_protocol }}</span>
            </span>
          </CadenceDataRow>
          <CadenceDataRow
            row-class="hud-data-row"
            label-class="hud-data-label"
            :label="labels.uplink_protocol"
          >
            <span class="hud-data-value">
              <span class="uppercase">{{ profile.uplink_protocol }}</span>
            </span>
          </CadenceDataRow>
          <CadenceDataRow
            row-class="hud-data-row"
            label-class="hud-data-label"
            :label="labels.packet_protocol"
          >
            <span class="hud-data-value">{{ profile.packet_protocol }}</span>
          </CadenceDataRow>
          <CadenceDataRow
            row-class="hud-data-row"
            label-class="hud-data-label"
            :label="labels.lifecycle"
          >
            <span class="hud-data-value">{{ profile.lifecycle }}</span>
          </CadenceDataRow>
        </div>

        <div v-if="profile.frame_parameters.length > 0" class="mt-5">
          <div class="hud-divider"></div>
          <p class="hud-label mb-3">{{ labels.frame_parameters }}</p>
          <div class="grid gap-x-8 gap-y-1 md:grid-cols-2">
            <CadenceDataRow
              v-for="parameter in profile.frame_parameters"
              :key="parameter.id"
              :row-id="parameter.id"
              row-class="hud-data-row"
              label-class="hud-data-label"
              :label="parameter.label"
            >
              <span class="hud-data-value">{{ parameter.value }}</span>
            </CadenceDataRow>
          </div>
        </div>
    </CadenceCard>

    <CadenceCard
      id="spacecraft-profile-applications"
      class="card bg-base-200 border border-base-300"
      body-class="card-body p-6"
    >
        <p class="hud-label">{{ labels.applications }}</p>
        <ul v-if="profile.applications.length > 0" class="mt-4 space-y-2">
          <li
            v-for="application in profile.applications"
            :id="application.id"
            :key="application.id"
            class="flex items-center gap-3 rounded border border-base-300 bg-base-100/40 p-3 text-sm border-l-2 border-l-primary/60"
          >
            <span class="hero-bolt h-4 w-4 text-primary/70"></span>
            <span class="font-medium">{{ application.label }}</span>
          </li>
        </ul>
        <p v-else class="mt-4 text-sm text-base-content/50 italic">
          {{ labels.no_applications }}
        </p>
    </CadenceCard>

    <CadenceCard
      v-if="versions.length > 1"
      id="spacecraft-profile-version-history-card"
      class="card bg-base-200 border border-base-300"
      body-class="card-body p-6"
    >
        <p class="hud-label">{{ labels.version_history }}</p>
        <CadenceTableFrame id="spacecraft-profile-version-history" class="mt-3">
          <thead>
            <tr>
              <th class="hud-label">{{ labels.version }}</th>
              <th class="hud-label">{{ labels.lifecycle }}</th>
              <th class="hud-label">{{ labels.downlink }}</th>
              <th class="hud-label">{{ labels.uplink }}</th>
            </tr>
          </thead>
          <tbody id="spacecraft-profile-version-history-body">
            <tr v-for="version in versions" :id="version.id" :key="version.id">
              <td class="font-mono text-sm">{{ version.version }}</td>
              <td class="font-mono text-sm text-base-content/70">{{ version.lifecycle }}</td>
              <td class="font-mono text-sm uppercase text-primary/80">
                {{ version.downlink_protocol }}
              </td>
              <td class="font-mono text-sm uppercase text-primary/80">
                {{ version.uplink_protocol }}
              </td>
            </tr>
          </tbody>
        </CadenceTableFrame>
    </CadenceCard>
  </div>
</template>
