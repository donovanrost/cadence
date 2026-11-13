<script setup lang="ts">
import { ApStatusMark } from "@/ui";
import type { WidgetDiagnostics } from "./api.ts";
import { actionText, cacheText, statusMark, warningText } from "./present.ts";

/** One widget: status mark + word, cache, the operator action, warnings in words; codes in details. */
defineProps<{ widget: WidgetDiagnostics }>();
</script>

<template>
  <li class="flex flex-col gap-1 border-t border-hairline px-4 py-3 first:border-t-0">
    <div class="flex flex-wrap items-baseline gap-3">
      <span class="inline-flex items-center gap-2 font-mono text-xs uppercase"
        ><ApStatusMark :state="statusMark[widget.status].state" />{{
          statusMark[widget.status].word
        }}</span
      >
      <span class="text-md font-semibold text-readout">{{
        widget.title ?? "Untitled widget"
      }}</span>
      <span v-if="cacheText(widget)" class="text-sm text-text-3">{{ cacheText(widget) }}</span>
    </div>
    <p v-for="a in actionText(widget)" :key="a" class="m-0 text-md text-text-2">{{ a }}</p>
    <p v-for="w in widget.warnings" :key="w.code" class="m-0 text-sm text-caution-text">
      {{ warningText(w) }}
    </p>
    <details
      v-if="widget.sources.length > 0 || widget.warnings.length > 0"
      class="text-sm text-text-3"
    >
      <summary class="cursor-pointer">Technical details</summary>
      <ul class="m-0 mt-1 list-none p-0 font-mono text-xs">
        <li v-for="(s, i) in widget.sources" :key="`s-${i}`">
          {{ s.logical_source ?? "source" }} · {{ s.status_code ?? "not run"
          }}<template v-if="s.severity"> · {{ s.severity }}</template
          ><template v-if="s.retryable !== null">
            · {{ s.retryable ? "retryable" : "not retryable" }}</template
          ><template v-if="s.warning_codes.length"> · {{ s.warning_codes.join(", ") }}</template>
        </li>
        <li v-for="w in widget.warnings" :key="`w-${w.code}`">{{ w.code }} · {{ w.severity }}</li>
      </ul>
    </details>
  </li>
</template>
