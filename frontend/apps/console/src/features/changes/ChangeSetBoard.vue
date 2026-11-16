<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import type { RemoteState } from "@/api";
import ApplyAside from "./ApplyAside.vue";
import ChangeList from "./ChangeList.vue";
import ChecksPanel from "./ChecksPanel.vue";
import ReviewPanel from "./ReviewPanel.vue";
import type { Preview, PreviewItem, SubmitResult } from "./actions.ts";
import { conversionStager } from "./review-block.ts";
import type { HeldChecks } from "./checks-view.ts";
import type { InUseMark } from "./refusals.ts";
import type { ChangeSet, ConfigState } from "./shapes.ts";

/** The open set: K1 changes and K2 checks, beside K3 Apply (or review, for a reviewer). */
const props = defineProps<{
  missionId: MissionId;
  config: ConfigState;
  changeSet: ChangeSet;
  preview: RemoteState<Preview>;
  /** ux B4: the last checks, while new ones run or failed for a moved version. */
  held: HeldChecks | null;
  /** "Checks done: …" once new results replace re-running ones. */
  checksDone: string | null;
  conflicts: ReadonlyMap<string, readonly PreviewItem[]>;
}>();
const emit = defineEmits<{ reload: []; result: [result: SubmitResult]; changed: [] }>();
/** U82: the archive row an apply-time in-use refusal is about (marked in K1 too). */
const inUse = ref<InUseMark | null>(null);
const reviewing = () =>
  props.changeSet.state === "in_review" && props.config.permissions.has("config.review");
</script>

<template>
  <div class="flex flex-wrap items-start gap-4">
    <div class="flex min-w-0 flex-[999_1_560px] flex-col gap-4">
      <!-- TEMPORARY (ux U79; deleted with 9ac6dc8ee): who staged a conversion batch. -->
      <p v-if="conversionStager(changeSet)" class="m-0 text-md text-text-3">
        {{ conversionStager(changeSet) }}
      </p>
      <ChangeList
        :mission-id="missionId"
        :config="config"
        :change-set="changeSet"
        :conflicts="conflicts"
        :in-use="inUse"
        @changed="emit('reload')"
      />
      <ChecksPanel
        :preview="preview"
        :held="held"
        :done="checksDone"
        :now-count="changeSet.staged_count"
        :left-by="`r${changeSet.base_revision}`"
        @retry="emit('reload')"
      />
    </div>
    <ReviewPanel
      v-if="reviewing()"
      :mission-id="missionId"
      :config="config"
      :change-set="changeSet"
      :preview="preview"
      class="sticky top-0 min-w-0 flex-[1_1_340px]"
      @result="emit('result', $event)"
      @changed="emit('changed')"
      @in-use="inUse = $event"
    />
    <ApplyAside
      v-else
      :mission-id="missionId"
      :config="config"
      :change-set="changeSet"
      :preview="preview"
      class="sticky top-0 min-w-0 flex-[1_1_340px]"
      :held="held"
      @result="emit('result', $event)"
      @changed="emit('changed')"
      @in-use="inUse = $event"
    />
  </div>
</template>
