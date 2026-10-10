<script setup lang="ts">
import { onBeforeUnmount, reactive, ref, shallowRef } from "vue";
import type { OpsPageNavigationPort, OpsPageReadPort } from "@cadence/plugin-sdk/ops-pages";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";
import { useOpsHeader } from "@cadence/plugin-sdk/page-header";
import { href as routeHref } from "@cadence/plugin-sdk/routes";
import CadenceOpsListBodyFrame from "@cadence/ui/CadenceOpsListBodyFrame.vue";
import { directoryHref, readDirectory, type Directory } from "./contracts";
import { stagesHref } from "../../shared/stages/links";
defineOptions({ inheritAttrs: false });
const props = defineProps<{
  directory: Directory;
  port: OpsPageNavigationPort;
  readPort: OpsPageReadPort;
}>();
const directory = shallowRef(props.directory),
  context = { ...props.directory.context },
  actor = props.directory.actor_id;
const filters = reactive({
    query: props.directory.query.query,
    state: props.directory.query.state,
  }),
  busy = ref(false),
  feedback = ref("");
let disposed = false;
onBeforeUnmount(() => {
  disposed = true;
});
function follow(event: MouseEvent, href: string) {
  if (!event.metaKey && !event.ctrlKey && !event.shiftKey && !event.altKey && event.button === 0) {
    event.preventDefault();
    if (!busy.value) props.port.navigate(href);
  }
}
function search() {
  if (!busy.value) props.port.navigate(directoryHref(context.missionId, { ...filters, after: "" }));
}
async function refresh() {
  if (busy.value) return;
  busy.value = true;
  feedback.value = "";
  try {
    const next = readDirectory(await props.readPort.read(), context);
    if (next.actor_id !== actor) throw Error();
    if (!disposed) directory.value = next;
  } catch {
    if (!disposed)
      feedback.value =
        "The stage directory could not be refreshed. Your previous view is still shown.";
  } finally {
    if (!disposed) busy.value = false;
  }
}
useOpsHeader("/missions/:mission_id/ops/commands/stages", () => ({
  description:
    "Prepare commands privately or collaborate in a shared stage. Submit reviewed drafts as formal requests when they are ready.",
  primary: {
    id: "stage-create-link",
    label: "Create stage",
    icon: "hero-plus",
    href: routeHref("/missions/:mission_id/ops/commands/stages/new", {
      mission_id: context.missionId,
    }),
  },
  refresh: { run: refresh, pending: busy.value },
}));
</script>
<template>
  <CadenceOpsViewport id="command-stages">
    <CadenceOpsListBodyFrame>
      <form
        id="stage-directory-filters"
        class="flex flex-wrap items-end gap-3"
        @submit.prevent="search"
      >
        <label class="flex-1 min-w-48 space-y-1 text-sm"
          >Find a stage<input
            id="stage-directory-query"
            v-model="filters.query"
            maxlength="240"
            class="input input-bordered w-full" /></label
        ><label class="space-y-1 text-sm"
          >State<select
            id="stage-directory-state"
            v-model="filters.state"
            class="select select-bordered"
          >
            <option value="">All states</option>
            <option value="draft">Draft</option>
            <option value="in_review">In review</option>
            <option value="ready_to_submit">Ready to submit</option>
            <option value="submitted">Submitted</option>
            <option value="canceled">Canceled</option>
          </select></label
        ><button class="btn btn-ghost" :disabled="busy">Apply filters</button>
      </form>
      <p v-if="feedback" role="alert" class="text-sm text-warning">{{ feedback }}</p>
      <p class="text-xs text-base-content/60">
        Private stages are visible only to their owner. Shared stages are available to mission
        managers.
      </p>
      <ul id="stage-directory-entries" class="divide-y divide-base-300 border-y border-base-300">
        <li v-for="stage in directory.stages.entries" :key="stage.id">
          <a
            :data-stage-id="stage.id"
            :href="stagesHref(context.missionId, stage.id)"
            class="flex flex-wrap items-center justify-between gap-3 py-4 hover:text-info"
            @click="follow($event, stagesHref(context.missionId, stage.id))"
            ><span class="min-w-0"
              ><strong class="block text-sm">{{ stage.name }}</strong
              ><span class="block break-all font-mono text-xs text-base-content/50">{{
                stage.id
              }}</span></span
            ><span class="flex gap-3 text-xs"
              ><span>{{ stage.visibility === "private" ? "Private" : "Shared" }}</span
              ><span>{{ stage.state.replaceAll("_", " ") }}</span></span
            ></a
          >
        </li>
      </ul>
      <p
        v-if="!directory.stages.entries.length"
        id="stage-directory-empty"
        class="py-8 text-sm text-base-content/60"
      >
        No stages match these filters.
      </p>
      <nav aria-label="Stage pages" class="flex flex-wrap gap-4 text-sm">
        <a
          v-if="directory.query.after"
          :href="directoryHref(context.missionId, { ...directory.query, after: '' })"
          @click="
            follow($event, directoryHref(context.missionId, { ...directory.query, after: '' }))
          "
          >First page</a
        ><a
          v-if="directory.stages.next_after"
          id="stage-directory-next"
          :href="
            directoryHref(context.missionId, {
              ...directory.query,
              after: directory.stages.next_after,
            })
          "
          @click="
            follow(
              $event,
              directoryHref(context.missionId, {
                ...directory.query,
                after: directory.stages.next_after,
              }),
            )
          "
          >Next 25 stages →</a
        >
      </nav>
    </CadenceOpsListBodyFrame>
  </CadenceOpsViewport>
</template>
