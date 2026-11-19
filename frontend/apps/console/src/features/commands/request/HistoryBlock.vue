<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { onMounted } from "vue";
import { ApButton } from "@/ui";
import { attemptLine, evidenceLine, technicalLines, verifierLine } from "./historyWords.ts";
import { useMemberHistory } from "./useMemberHistory.ts";

/**
 * One command's block in a target's History (ux U70): Attempts then Verifiers, both oldest first,
 * each verifier's matched record on a text-3 line, ids and phases under Technical details.
 */
const props = defineProps<{
  missionId: MissionId;
  requestId: string;
  title: string;
  spacecraft: string | null;
}>();
const h = useMemberHistory(
  () => props.missionId,
  () => props.requestId,
);
onMounted(h.load);
</script>

<template>
  <section class="flex flex-col gap-2 border-t border-hairline pt-3 first:border-t-0 first:pt-0">
    <h3 class="m-0 font-mono text-sm font-semibold text-readout">{{ title }}</h3>
    <p
      v-if="h.state.value.status === 'loading'"
      class="m-0 font-mono text-xs text-text-4 uppercase"
    >
      Loading history…
    </p>
    <p v-else-if="h.state.value.status === 'failed'" class="m-0 text-sm text-caution-text">
      Couldn't load this history: {{ h.state.value.error }}
    </p>
    <template v-else>
      <span class="ap-label">Attempts</span>
      <ApButton
        v-if="h.state.value.value.attemptsNext"
        size="compact"
        variant="ghost"
        class="self-start"
        :disabled="h.state.value.more"
        @click="h.earlier"
        >Show earlier attempts</ApButton
      >
      <p v-if="!h.state.value.value.attempts.length" class="m-0 text-sm text-text-3">
        Not released yet.
      </p>
      <ul class="m-0 list-none p-0">
        <li
          v-for="a in h.state.value.value.attempts"
          :key="a.attempt_id"
          class="font-mono text-sm text-text-2"
        >
          {{ attemptLine(a, spacecraft) }}
        </li>
      </ul>
      <span class="ap-label">Verifiers</span>
      <p v-if="!h.state.value.value.verifiers.length" class="m-0 text-sm text-text-3">
        No verifiers yet.
      </p>
      <ul class="m-0 list-none p-0">
        <li v-for="v in h.state.value.value.verifiers" :key="v.instance_id" class="flex flex-col">
          <span class="font-mono text-sm text-text-2">{{ verifierLine(v) }}</span>
          <span
            v-if="evidenceLine(v)"
            class="font-mono text-xs"
            :class="evidenceLine(v)?.crit ? 'text-crit-text' : 'text-text-3'"
            >{{ evidenceLine(v)?.text
            }}<span v-if="evidenceLine(v)?.caution" class="text-caution-text">
              · {{ evidenceLine(v)?.caution }}</span
            ></span
          >
        </li>
      </ul>
      <ApButton
        v-if="h.state.value.value.verifiersNext"
        size="compact"
        variant="ghost"
        class="self-start"
        :disabled="h.state.value.more"
        @click="h.later"
        >Show later verifiers</ApButton
      >
      <p v-if="h.pageError.value" class="m-0 text-sm text-caution-text">{{ h.pageError.value }}</p>
      <details class="text-xs text-text-3">
        <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
        <p
          v-for="line in technicalLines(
            h.state.value.value.attempts,
            h.state.value.value.verifiers,
          )"
          :key="line"
          class="m-0 pt-1 font-mono break-all"
        >
          {{ line }}
        </p>
      </details>
    </template>
  </section>
</template>
