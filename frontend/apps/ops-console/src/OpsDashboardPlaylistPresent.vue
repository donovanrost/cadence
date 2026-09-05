<script setup lang="ts">
type FreshnessSignal = {
  id: string;
  visible: boolean;
  icon: string;
  copy: string;
};

type PlaylistPosition = {
  id: string;
  current: number;
  total: number;
};

type NextAction = {
  id: string;
  label: string;
};

type UnavailableState = {
  id: string;
  state: string;
  icon: string;
  title: string;
  copy: string;
};

type Page = {
  id: string;
  wallboard_mode: boolean;
  mode_label: string;
  playlist_name: string;
  freshness_signal: FreshnessSignal;
  position: PlaylistPosition;
  next_action: NextAction;
  unavailable: UnavailableState;
};

type CurrentDashboard = {
  dashboard_id: string;
  name: string;
  available: boolean;
  path: string;
  frame_id: string;
};

defineProps<{
  page: Page;
  current_dashboard: CurrentDashboard;
}>();

const emit = defineEmits<{
  "next-dashboard": [];
}>();
</script>

<template>
  <section
    :id="page.id"
    class="flex h-full min-h-0 flex-col bg-base-100"
    :data-wallboard-mode="String(page.wallboard_mode)"
  >
    <header
      class="flex shrink-0 flex-wrap items-center gap-3 border-b border-warning/35 bg-warning/10 px-4 py-2"
    >
      <div class="min-w-0 flex-1">
        <p class="hud-label">{{ page.mode_label }} · {{ page.playlist_name }}</p>
        <p class="truncate text-sm font-semibold">{{ current_dashboard.name }}</p>
      </div>
      <div
        :id="page.freshness_signal.id"
        :data-freshness-visible="String(page.freshness_signal.visible)"
        class="flex items-center gap-2 border border-warning/30 bg-base-100 px-3 py-1.5 text-xs"
      >
        <span :class="[page.freshness_signal.icon, 'h-4 w-4 text-warning']"></span>
        <span>{{ page.freshness_signal.copy }}</span>
      </div>
      <span :id="page.position.id" class="font-mono text-xs">
        {{ page.position.current }}/{{ page.position.total }}
      </span>
      <button
        :id="page.next_action.id"
        type="button"
        class="btn btn-ghost btn-xs"
        @click="emit('next-dashboard')"
      >
        {{ page.next_action.label }}
      </button>
    </header>
    <iframe
      v-if="current_dashboard.available"
      :id="current_dashboard.frame_id"
      :title="current_dashboard.name"
      :src="current_dashboard.path"
      class="min-h-0 flex-1 w-full border-0"
      :data-dashboard-id="current_dashboard.dashboard_id"
    ></iframe>
    <div
      v-else
      :id="page.unavailable.id"
      :data-dashboard-state="page.unavailable.state"
      class="flex min-h-0 flex-1 items-center justify-center bg-error/5 p-8"
    >
      <div class="max-w-xl border border-error/35 bg-base-100 p-6 text-center">
        <span :class="[page.unavailable.icon, 'mx-auto h-8 w-8 text-error']"></span>
        <h2 class="mt-3 text-lg font-semibold">{{ page.unavailable.title }}</h2>
        <p class="mt-2 text-sm text-base-content/60">{{ page.unavailable.copy }}</p>
      </div>
    </div>
  </section>
</template>
