<script setup lang="ts">
import { ApButton, ApCallout, ApListRow, ApPanel } from "@/ui";
import { findingTitle, type Findings } from "./findings.ts";

/**
 * D4 · Needs a decision (Contacts.md): one row per finding, the server's sentence, and `Open in
 * Plan` (no fix proposals yet). Hidden by the screen when M22 isn't available.
 */
defineProps<{ findings: Findings; label: string }>();
const day = (iso: string | null) => (iso ?? new Date().toISOString()).slice(0, 10);
</script>

<template>
  <ApPanel index="D4" title="Needs a decision" pane flush>
    <ApCallout v-if="findings.findings.length === 0" tone="nominal">
      No conflicts or gaps in the next {{ label }}.
    </ApCallout>
    <ul v-else class="m-0 list-none p-0">
      <ApListRow
        v-for="f in findings.findings"
        :key="f.id"
        :state="f.severity === 'critical' ? 'crit' : 'caution'"
        :title="findingTitle(f)"
        :sentence="f.message"
      >
        <template #action>
          <ApButton
            size="compact"
            variant="secondary"
            :to="{ name: 'ops.contacts.plan', query: { day: day(f.at) } }"
            >Open in Plan</ApButton
          >
        </template>
      </ApListRow>
    </ul>
    <p
      v-if="findings.truncated"
      class="m-0 border-t border-hairline px-4 py-2 text-sm text-caution-text"
    >
      Too many passes to check them all; narrow the window.
    </p>
  </ApPanel>
</template>
