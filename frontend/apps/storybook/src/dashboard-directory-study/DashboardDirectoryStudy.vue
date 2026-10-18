<script setup lang="ts">
import { computed, ref } from "vue";
import DirectoryHeading from "./DirectoryHeading.vue";
import DirectoryNotice from "./DirectoryNotice.vue";
import DirectoryResults from "./DirectoryResults.vue";
import DirectoryToolbar from "./DirectoryToolbar.vue";
import DuplicateDialog from "./DuplicateDialog.vue";
import FirstRun from "./FirstRun.vue";
import ShortcutArea from "./ShortcutArea.vue";
import ShortcutRail from "./ShortcutRail.vue";
import type { StudyDashboard } from "./fixtures";
import type { DirectoryStudy, Presentation, QuickAccess } from "./state";

const props = defineProps<{
  study: DirectoryStudy;
  quickAccess: QuickAccess;
  presentation: Presentation;
}>();
const duplicating = ref<StudyDashboard | null>(null);
const rail = computed(() => props.quickAccess === "rail");
// Shortcuts above the list give way once the person is searching; the rail stays.
const above = computed(() => {
  const variant = props.quickAccess;
  return variant === "none" || variant === "rail" || props.study.filtered ? null : variant;
});

function duplicate(name: string) {
  if (duplicating.value) props.study.actions.duplicate(duplicating.value.id, name);
  duplicating.value = null;
}
</script>

<template>
  <div class="space-y-4">
    <DirectoryHeading :author="study.author" />
    <DirectoryNotice
      v-if="study.notice"
      :notice="study.notice"
      @dismiss="study.actions.dismissNotice"
    />
    <FirstRun v-if="study.empty" :author="study.author" />
    <template v-else>
      <ShortcutArea v-if="above" :study="study" :variant="above" />
      <div :class="rail ? 'grid items-start gap-4 xl:grid-cols-[minmax(0,1fr)_20rem]' : ''">
        <div class="min-w-0 space-y-4">
          <DirectoryToolbar :study="study" />
          <DirectoryResults
            :study="study"
            :presentation="presentation"
            @duplicate="duplicating = $event"
          />
        </div>
        <ShortcutRail v-if="rail" :study="study" />
      </div>
    </template>
    <DuplicateDialog :source="duplicating" @close="duplicating = null" @confirm="duplicate" />
  </div>
</template>
