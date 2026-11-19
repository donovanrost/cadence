<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApCallout } from "@/ui";
import type { MatchedRevision } from "./matchedRevision.ts";
import { matchVerdict, openLabel, openOtherLabel, otherDatabaseVerdict } from "./matchedWords.ts";

/**
 * ux U99 (#119): the import matched a revision that already exists. With `own`, this run made its
 * own revision in another catalog database and the line names both. Every line is text: the
 * rejection reason is a person's free text and is never rendered as HTML.
 */
const props = defineProps<{
  match: MatchedRevision;
  own?:
    | Readonly<{
        number: number;
        database?: Readonly<{ id: string; name: string | null }> | null | undefined;
      }>
    | undefined;
}>();
const verdict = computed(() =>
  props.own ? otherDatabaseVerdict(props.own, props.match) : matchVerdict(props.match),
);
const open = computed(() => (props.own ? openOtherLabel(props.match) : openLabel(props.match)));
</script>

<template>
  <ApCallout :tone="verdict.tone">
    {{ verdict.text }}
    <ApButton
      size="compact"
      variant="ghost"
      :to="{ name: 'setup.catalog.model', params: { revisionId: match.model_revision_id } }"
      >{{ open }}</ApButton
    >
  </ApCallout>
</template>
