<script setup lang="ts">
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { ApButton, ApField, ApSelect, ApTextarea } from "@/ui";
import { fetchPeople } from "@/features/alarms/index.ts";

/**
 * Person picker for Assign (optional note) and Hand off (required note; people who can approve
 * commands listed first, Mobile.md). `to: null` = unassign / leave for the next shift.
 */
const props = defineProps<{ mode: "assign" | "hand_off"; busy: boolean; stacked?: boolean }>();
const emit = defineEmits<{ submit: [to: string | null, note: string]; cancel: [] }>();
const scope = useMissionScope();
const people = useRemoteQuery(
  computed(() => scope.value.organization.id),
  (org, signal) => fetchPeople(org, signal),
);

const pick = ref("");
const note = ref("");
const options = computed(() => {
  const members =
    people.state.value.status === "ready" ? [...people.state.value.value.members] : [];
  if (props.mode === "hand_off")
    members.sort(
      (a, b) =>
        Number(b.capabilities.includes("command.approve")) -
        Number(a.capabilities.includes("command.approve")),
    );
  return [
    { value: "", label: "Choose a person…" },
    {
      value: "none",
      label: props.mode === "assign" ? "Nobody (unassign)" : "Next shift (unassigned)",
    },
    ...members.map((m) => ({ value: m.user_id, label: m.display_name ?? m.user_id })),
  ];
});
const noteRequired = computed(() => props.mode === "hand_off");
const ready = computed(
  () => pick.value !== "" && (!noteRequired.value || note.value.trim() !== ""),
);
const why = computed(() =>
  pick.value === "" ? "Choose a person first" : "A hand-off needs a note",
);
function submit() {
  if (ready.value) emit("submit", pick.value === "none" ? null : pick.value, note.value.trim());
}
</script>

<template>
  <form class="flex flex-col gap-2" @submit.prevent="submit">
    <ApSelect
      v-model="pick"
      :label="mode === 'assign' ? 'Assign to' : 'Hand off to'"
      size="compact"
      :options="options"
    />
    <ApTextarea
      v-if="noteRequired"
      v-model="note"
      label="Hand-off note"
      required
      :rows="3"
      placeholder="What the next person needs to know"
    />
    <ApField v-else v-model="note" label="Note (optional)" />
    <div class="flex gap-2" :class="stacked ? 'grid grid-cols-2' : ''">
      <ApButton
        :size="stacked ? 'commit' : 'compact'"
        :class="stacked ? 'min-h-12 w-full' : ''"
        type="submit"
        :disabled="!ready || busy"
        :disabled-reason="busy ? 'Working…' : why"
      >
        {{ mode === "assign" ? "Assign" : "Hand off" }}
      </ApButton>
      <ApButton
        :size="stacked ? 'commit' : 'compact'"
        :class="stacked ? 'min-h-12 w-full' : ''"
        variant="ghost"
        @click="emit('cancel')"
        >Cancel</ApButton
      >
    </div>
  </form>
</template>
