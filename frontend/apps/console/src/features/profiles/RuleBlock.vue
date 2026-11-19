<script setup lang="ts">
import { computed } from "vue";
import { ApChip, ApPanel, ApTag, formatCount } from "@/ui";
import type { ProfileRule } from "./detail.ts";

/** One profile routing rule as a sentence (Profile.md P2), with generated samples and route count. */
const props = defineProps<{ rule: ProfileRule; profileName: string; index: string }>();
const legs = computed(() => props.rule.legs.map((l) => `${l.direction} · ${l.role}`).join(" · "));
const extra = computed(() => props.rule.route_count - props.rule.samples.length);
</script>

<template>
  <ApPanel
    :index="index"
    :title="rule.label"
    :meta="`1 rule → ${formatCount(rule.route_count)} routes`"
  >
    <!-- P7 (#313, ux §10): a disabled rule is dimmed with a DISABLED tag (off: mark + word); the
      console's sentence stays as its secondary line. -->
    <template v-if="!rule.enabled" #header><ApTag state="off" label="Disabled" /></template>
    <div class="flex flex-col gap-3">
      <div class="flex flex-col gap-3" :class="rule.enabled ? '' : 'opacity-60'">
        <p class="m-0 font-mono text-md leading-relaxed text-readout">
          <span class="text-text-4">FOR EACH</span> spacecraft in {{ profileName }}<br />
          <span class="text-text-4">AND EACH</span> station in [{{
            rule.stations.map((s) => s.code ?? s.name).join(", ")
          }}]<br />
          <span class="text-text-4">ROUTE</span> {{ legs }}<br />
          <span class="text-text-4">NAME</span> "{{ rule.name_template }}"
        </p>
        <div class="flex flex-wrap items-center gap-2">
          <span class="ap-label">Generates</span>
          <ApChip v-for="sample in rule.samples" :key="sample">{{ sample }}</ApChip>
          <span v-if="extra > 0" class="text-sm text-text-3">+ {{ formatCount(extra) }}</span>
        </div>
      </div>
      <!-- The explanation, not disabled content: outside the dimmed block, full opacity (mms-ux). -->
      <p v-if="!rule.enabled" data-rule-disabled class="m-0 text-sm text-text-3">
        This rule is disabled; it generates no routes.
      </p>
    </div>
  </ApPanel>
</template>
