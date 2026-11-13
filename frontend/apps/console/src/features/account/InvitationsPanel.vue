<script setup lang="ts">
import { ref } from "vue";
import { useRemoteQuery } from "@/api";
import { ApCallout, ApPanel } from "@/ui";
import InvitationRow from "./InvitationRow.vue";
import { fetchMyInvitations } from "./invitations.ts";

/** People.md Account: pending invitations to other organizations, shown first, only when there are any. */
const list = useRemoteQuery(() => true as const, fetchMyInvitations);
const note = ref<string | null>(null);
function changed(text: string | null) {
  note.value = text;
  list.refetch();
}
</script>

<template>
  <ApCallout v-if="note" tone="info">{{ note }}</ApCallout>
  <ApPanel
    v-if="list.state.value.status === 'ready' && list.state.value.value.length > 0"
    index="A0"
    title="Invitations"
    :meta="`${list.state.value.value.length} pending`"
    flush
  >
    <ul class="m-0 list-none p-0">
      <InvitationRow
        v-for="i in list.state.value.value"
        :key="i.id"
        :invitation="i"
        @changed="changed"
      />
    </ul>
  </ApPanel>
</template>
