<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import type { RemoteState } from "@/api";
import ApplyAside from "./ApplyAside.vue";
import ChangeList from "./ChangeList.vue";
import ChecksPanel from "./ChecksPanel.vue";
import ReviewPanel from "./ReviewPanel.vue";
import type { Preview, PreviewItem, SubmitResult } from "./actions.ts";
import type { HeldChecks } from "./checks-view.ts";
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
const reviewing = () =>
  props.changeSet.state === "in_review" && props.config.permissions.has("config.review");
</script>

<template>
  <div class="flex flex-wrap items-start gap-4">
    <div class="flex min-w-0 flex-[999_1_560px] flex-col gap-4">
      <ChangeList
        :mission-id="missionId"
        :config="config"
        :change-set="changeSet"
        :conflicts="conflicts"
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
      class="sticky top-0 min-w-0 flex-[1_1_340px]"
      @result="emit('result', $event)"
      @changed="emit('changed')"
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
    />
  </div>
</template>
