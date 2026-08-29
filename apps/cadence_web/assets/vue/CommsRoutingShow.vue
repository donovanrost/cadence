<script setup lang="ts">
import CadenceBreadcrumbs from "./ui/components/CadenceBreadcrumbs.vue"
import CadencePageHeaderFrame from "./ui/components/CadencePageHeaderFrame.vue"
import CadenceCard from "./ui/components/CadenceCard.vue"
import CadenceDataRow from "./ui/components/CadenceDataRow.vue"
import CadenceDetailsFrame from "./ui/components/CadenceDetailsFrame.vue"
import StatusBadge from "./StatusBadge.vue"

type Breadcrumb = {
  label: string
  href: string | null
}

type Navigation = {
  breadcrumbs: Breadcrumb[]
}

type Detail = {
  label: string
  value: string
}

type RoutingRule = {
  display_name: string
  routing_rule_id: string
  state: {
    label: string
    tone: "info" | "ready"
  }
  section_title: string
  description: string
  details: Detail[]
  runtime_artifacts_title: string
  runtime_artifacts: Detail[]
}

type RoutingRuleEvent = {
  event_type: string
  occurred_at: string
}

defineProps<{
  navigation: Navigation
  rule: RoutingRule
  events: RoutingRuleEvent[]
}>()
</script>

<template>
  <div id="comms-routing-show-surface" class="space-y-6">
    <CadencePageHeaderFrame variant="compact">
      <div class="flex items-end justify-between gap-4">
        <div>
          <CadenceBreadcrumbs>
            <template
              v-for="(breadcrumb, index) in navigation.breadcrumbs"
              :key="`${index}-${breadcrumb.label}`"
            >
              <span v-if="index > 0" class="text-base-content/20" aria-hidden="true">/</span>
              <span v-if="breadcrumb.href === null" class="text-primary/90">
                {{ breadcrumb.label }}
              </span>
              <a
                v-else
                :href="breadcrumb.href"
                data-phx-link="redirect"
                data-phx-link-state="push"
                class="hover:text-primary transition-colors"
              >{{ breadcrumb.label }}</a>
            </template>
          </CadenceBreadcrumbs>

          <h1 class="mt-2 text-2xl font-bold text-base-content tracking-tight">
            {{ rule.display_name }}
          </h1>
          <p class="mt-1 max-w-3xl text-sm text-base-content/70">
            {{ rule.routing_rule_id }}
          </p>
        </div>

        <div class="flex items-center gap-2">
          <StatusBadge :status="rule.state.tone" :label="rule.state.label" />
        </div>
      </div>
    </CadencePageHeaderFrame>

    <div class="grid gap-4 xl:grid-cols-[1fr_22rem]">
      <CadenceCard class="card bg-base-200 border border-base-300" body-class="card-body p-6">
          <p class="hud-label">{{ rule.section_title }}</p>
          <p class="text-sm text-base-content/70">
            {{ rule.description }}
          </p>

          <div class="mt-6 space-y-1">
            <CadenceDataRow
              v-for="detail in rule.details"
              :key="detail.label"
              row-class="hud-data-row"
              label-class="hud-data-label"
              :label="detail.label"
            >
              <span class="hud-data-value">{{ detail.value }}</span>
            </CadenceDataRow>
          </div>

          <CadenceDetailsFrame class="mt-6 rounded border border-base-300 bg-base-100/40 p-4 text-sm">
            <summary class="cursor-pointer hud-label hover:text-primary">
              {{ rule.runtime_artifacts_title }}
            </summary>
            <div class="mt-3 space-y-1">
              <CadenceDataRow
                v-for="artifact in rule.runtime_artifacts"
                :key="artifact.label"
                row-class="hud-data-row"
                label-class="hud-data-label"
                :label="artifact.label"
              >
                <span class="hud-data-value">{{ artifact.value }}</span>
              </CadenceDataRow>
            </div>
          </CadenceDetailsFrame>
      </CadenceCard>

      <CadenceCard class="card bg-base-200 border border-base-300" body-class="card-body p-6">
          <p class="hud-label">Events</p>
          <div id="routing-rule-events" class="space-y-2">
            <div
              v-for="(event, index) in events"
              :key="`${event.event_type}-${event.occurred_at}-${index}`"
              class="rounded-[2px] border border-base-300 bg-base-100/40 p-3"
            >
              <p class="font-mono text-xs text-base-content/70">{{ event.event_type }}</p>
              <p class="mt-1 text-xs text-base-content/60">{{ event.occurred_at }}</p>
            </div>
          </div>
      </CadenceCard>
    </div>
  </div>
</template>
