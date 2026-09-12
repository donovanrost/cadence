<script setup lang="ts">
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceDataRow from "@cadence/ui/CadenceDataRow.vue";
import CadenceDetailsFrame from "@cadence/ui/CadenceDetailsFrame.vue";
import StatusBadge from "../../shared/StatusBadge.vue";

type Breadcrumb = {
  label: string;
  href: string | null;
};

type Navigation = {
  breadcrumbs: Breadcrumb[];
};

type Detail = {
  label: string;
  value: string;
};

type RoutingRule = {
  display_name: string;
  routing_rule_id: string;
  state: {
    label: string;
    tone: "info" | "ready";
  };
  section_title: string;
  description: string;
  details: Detail[];
  runtime_artifacts_title: string;
  runtime_artifacts: Detail[];
};

type RoutingRuleEvent = {
  event_type: string;
  occurred_at: string;
};

defineProps<{
  navigation: Navigation;
  rule: RoutingRule;
  events: RoutingRuleEvent[];
}>();
</script>

<template>
  <div id="comms-routing-show-surface" class="space-y-6">
    <CadencePageHeading :breadcrumbs="navigation.breadcrumbs">
      <template #title>{{ rule.display_name }}</template>
      <template #description>{{ rule.routing_rule_id }}</template>
      <template #actions
        ><StatusBadge :status="rule.state.tone" :label="rule.state.label"
      /></template>
    </CadencePageHeading>

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
