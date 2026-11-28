<script setup lang="ts">
import { computed } from "vue";
import type { SessionOrganization } from "@/api/session.ts";
import { ApButton, formatShort } from "@/ui";
import { noticeWords, organizationLink, type Notice } from "./notices.ts";

/** One notice: its sentence (the organization opens when the session can), when, and Mark read. */
const props = defineProps<{
  notice: Notice;
  organizations: readonly SessionOrganization[];
  busy: boolean;
}>();
defineEmits<{ read: [] }>();
const words = computed(() => noticeWords(props.notice));
const org = computed(() => organizationLink(props.notice, props.organizations));
const when = (iso: string) => formatShort(new Date(iso));
</script>

<template>
  <li class="flex flex-wrap items-center gap-3 border-t border-hairline px-4 py-3 first:border-t-0">
    <span
      class="min-w-0 flex-1 text-md"
      :class="notice.read_at === null ? 'text-readout' : 'text-text-2'"
      >{{ words.before
      }}<RouterLink
        v-if="org.to"
        :to="org.to"
        class="font-semibold text-primary no-underline hover:underline"
        >{{ org.name }}</RouterLink
      ><span v-else class="font-semibold">{{ org.name }}</span
      >{{ words.after }}
      <span class="font-mono text-xs text-text-3">{{ when(notice.created_at) }}</span>
    </span>
    <ApButton
      v-if="notice.read_at === null"
      size="compact"
      :disabled="busy"
      disabled-reason="Working…"
      @click="$emit('read')"
      >Mark read</ApButton
    >
    <span v-else class="font-mono text-xs text-text-3">Read {{ when(notice.read_at) }}</span>
  </li>
</template>
