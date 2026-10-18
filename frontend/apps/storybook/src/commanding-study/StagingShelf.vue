<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import type { Execution, StagedItem } from "./fixtures";
defineProps<{
  staged: StagedItem[];
  execution: Execution[];
  active: "stage" | "execution";
  reviewing: boolean;
  confirmed: boolean;
}>();
const emit = defineEmits<{
  tab: [value: "stage" | "execution"];
  remove: [id: number];
  move: [id: number, offset: number];
  review: [];
  cancelReview: [];
  confirm: [value: boolean];
  release: [];
  advance: [];
  collapse: [];
}>();
function confirm(event: Event) {
  if (event.target instanceof HTMLInputElement) emit("confirm", event.target.checked);
}
</script>
<template>
  <section class="study-pane study-staging" aria-label="Command stage and execution">
    <header class="study-pane-heading study-shelf-heading">
      <div class="study-shelf-tabs" aria-label="Command work" role="group">
        <button type="button" :aria-pressed="active === 'stage'" @click="emit('tab', 'stage')">
          Pass preparation<span class="study-count">{{ staged.length }}</span>
        </button>
        <button
          type="button"
          :aria-pressed="active === 'execution'"
          @click="emit('tab', 'execution')"
        >
          Execution<span class="study-count">{{ execution.length }}</span>
        </button>
      </div>
      <div class="study-toolbar-actions">
        <template v-if="active === 'stage'">
          <span v-if="!reviewing" class="study-fine-print">Private draft stage</span>
          <CadenceButton
            v-if="!reviewing"
            id="study-review-stage"
            size="xs"
            variant="outline"
            :disabled="!staged.length"
            @click="emit('review')"
            >Review {{ staged.length }} commands<span
              class="hero-arrow-right study-icon-small"
              aria-hidden="true"
          /></CadenceButton>
          <CadenceButton v-else size="xs" variant="quiet" @click="emit('cancelReview')"
            >Back to stage</CadenceButton
          >
        </template>
        <CadenceButton
          v-else
          size="xs"
          variant="outline"
          :disabled="
            !execution.some(
              (item) => item.status === 'Queued' || item.status === 'Awaiting verification',
            )
          "
          @click="emit('advance')"
          >Advance simulation<span class="hero-forward study-icon-small" aria-hidden="true"
        /></CadenceButton>
        <CadenceButton
          size="xs"
          variant="quiet"
          aria-label="Minimize command shelf"
          @click="emit('collapse')"
          ><span class="hero-chevron-down study-icon-small" aria-hidden="true"
        /></CadenceButton>
      </div>
    </header>
    <div class="study-scroll">
      <table
        class="study-command-table"
        :aria-label="active === 'stage' ? 'Staged commands' : 'Simulated execution'"
      >
        <thead>
          <tr>
            <th scope="col">#</th>
            <th scope="col">Spacecraft / endpoint</th>
            <th scope="col">Command</th>
            <th scope="col">Setting</th>
            <th scope="col">
              {{ active === "stage" ? "Release requirements" : "Execution state" }}
            </th>
            <th scope="col"><span class="sr-only">Actions</span></th>
          </tr>
        </thead>
        <tbody v-if="active === 'stage'">
          <tr v-for="(item, index) in staged" :key="item.id" :data-staged-item="item.id">
            <td class="study-row-number">{{ String(index + 1).padStart(2, "0") }}</td>
            <td>
              <strong class="study-mono">{{ item.target.id }}</strong
              ><small>{{ item.target.endpoint }}</small>
            </td>
            <td>
              <code>{{ item.command.id }}</code
              ><small>{{ item.command.title }}</small>
            </td>
            <td class="study-mono">{{ item.value || "No arguments" }}</td>
            <td>
              <span :class="{ 'study-warning': item.command.hazardous }">{{
                item.command.hazardous
                  ? "Approval required"
                  : item.target.contact
                    ? "Validate at release"
                    : "Contact required"
              }}</span>
            </td>
            <td>
              <div v-if="!reviewing" class="study-row-actions">
                <CadenceButton
                  size="xs"
                  variant="quiet"
                  :disabled="index === 0"
                  :aria-label="'Move command ' + (index + 1) + ' earlier'"
                  @click="emit('move', item.id, -1)"
                  ><span class="hero-arrow-up study-icon-small" aria-hidden="true"
                /></CadenceButton>
                <CadenceButton
                  size="xs"
                  variant="quiet"
                  :disabled="index === staged.length - 1"
                  :aria-label="'Move command ' + (index + 1) + ' later'"
                  @click="emit('move', item.id, 1)"
                  ><span class="hero-arrow-down study-icon-small" aria-hidden="true"
                /></CadenceButton>
                <CadenceButton
                  size="xs"
                  variant="quiet"
                  :aria-label="'Remove staged command ' + (index + 1)"
                  @click="emit('remove', item.id)"
                  ><span class="hero-x-mark study-icon-small" aria-hidden="true"
                /></CadenceButton>
              </div>
            </td>
          </tr>
        </tbody>
        <tbody v-else>
          <tr v-for="(item, index) in execution" :key="item.id" :data-execution-item="item.id">
            <td class="study-row-number">{{ String(index + 1).padStart(2, "0") }}</td>
            <td>
              <strong class="study-mono">{{ item.target.id }}</strong
              ><small>{{ item.target.endpoint }}</small>
            </td>
            <td>
              <code>{{ item.command.id }}</code
              ><small>{{ item.command.title }}</small>
            </td>
            <td class="study-mono">{{ item.value || "No arguments" }}</td>
            <td colspan="2">
              <span class="study-execution-state" :data-state="item.status">
                <span
                  :class="[
                    item.status === 'Verified'
                      ? 'hero-check-circle'
                      : item.status === 'Awaiting verification'
                        ? 'hero-arrow-up-right'
                        : 'hero-clock',
                    'study-icon-small',
                  ]"
                  aria-hidden="true"
                />{{ item.status }}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
      <div v-if="active === 'stage' ? !staged.length : !execution.length" class="study-empty">
        {{
          active === "stage"
            ? "Choose a command and stage it for the selected spacecraft."
            : "Reviewed commands appear here when added to the simulated queue."
        }}
      </div>
    </div>
    <footer v-if="reviewing && active === 'stage'" class="study-review-bar">
      <label
        ><input id="study-review-confirm" type="checkbox" :checked="confirmed" @change="confirm" />I
        reviewed these {{ staged.length }} target / command pairs.</label
      >
      <CadenceButton size="sm" variant="primary" :disabled="!confirmed" @click="emit('release')"
        >Queue in simulation<span class="hero-arrow-right study-icon-small" aria-hidden="true"
      /></CadenceButton>
    </footer>
  </section>
</template>
