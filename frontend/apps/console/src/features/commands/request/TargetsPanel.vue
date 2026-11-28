<script setup lang="ts">
import { computed, toRef } from "vue";
import { describeApiError, type MissionId } from "@/api/index.ts";
import { ApButton, ApPanel, ApRemote, ApStatusMark, ApTag, formatCount } from "@/ui";
import { useFleet } from "@/features/fleet/index.ts";
import type { Group, GroupTarget } from "../groups/show.ts";
import { memberStageWord, STAGE_STATE } from "../groups/words.ts";
import { refusalLine } from "../groups/release.ts";
import { targetVerifyTime } from "../groups/verifyTimes.ts";
import { targetStageWord } from "../groups/expiry.ts";
import { WITHDRAWN_AFTER_GO_TAG } from "../groups/withdrawn.ts";
import { ownValuesText } from "./ownValues.ts";
import { useCatalogArgs } from "./useCatalogArgs.ts";
import { useGroupTargets } from "./useGroupPages.ts";
import TargetMatrix from "./TargetMatrix.vue";

/**
 * U1 · Targets (CommandFlow C3): the matrix and each target's trail. #795: a page of targets at a
 * time in target order (Load more reads on), re-read whenever a target's stage moves.
 */
const props = defineProps<{ group: Group; missionId: MissionId }>();
defineEmits<{ history: [target: GroupTarget] }>();
const missionId = toRef(props, "missionId");
const pages = useGroupTargets(missionId, toRef(props, "group"));
const loaded = computed(() =>
  pages.state.value.status === "ready" ? pages.state.value.value.items : [],
);
/** U1 matrix places targets by plane and slot from the fleet read. */
const fleet = useFleet(missionId);
const fleetRows = computed(() =>
  fleet.state.value.status === "ready" ? fleet.state.value.value.spacecraft : [],
);
const pos = (n: number) => String(n + 1).padStart(2, "0");
/** U46 (b): a member's latest named-release stop, under its target. */
const refusalOf = (t: GroupTarget) => {
  const r = t.members.find((m) => m.release_refusal)?.release_refusal;
  return r ? refusalLine(r, { spacecraft: t.name }) : null;
};
/** ux C2: the commands this target sends with its own values, worded as Approve words them. */
const argsOf = useCatalogArgs(missionId, toRef(props, "group"));
const ownOf = (t: GroupTarget) =>
  props.group.commands.flatMap((c) => {
    const values = ownValuesText(c, t.spacecraft_id, argsOf(c.command_id));
    return values === null ? [] : [{ position: c.position, name: c.name ?? c.command_id, values }];
  });
</script>

<template>
  <ApPanel index="U1" title="Targets" :meta="formatCount(group.target_count)" flush>
    <ApRemote
      :state="pages.state.value"
      loading-label="Loading the targets…"
      @retry="pages.refetch"
    >
      <template #default="{ value: page }">
        <TargetMatrix :group="group" :targets="loaded" :fleet="fleetRows" />
        <p
          v-if="pages.refreshError.value"
          role="status"
          class="m-0 border-t border-hairline px-4 py-2 text-sm text-caution-text"
        >
          Couldn't refresh the targets: {{ describeApiError(pages.refreshError.value) }}. Showing
          what was read before.
        </p>
        <ul class="m-0 list-none border-t border-hairline p-0">
          <li
            v-for="t in page.items"
            :key="t.spacecraft_id"
            class="grid grid-cols-[14px_200px_minmax(0,1fr)_auto_auto] items-baseline gap-3 border-t border-hairline-faint px-4 py-2 first:border-t-0"
          >
            <ApStatusMark :state="STAGE_STATE[t.stage]" class="self-center" />
            <span class="font-mono text-md text-readout"
              >{{ t.name ?? "Unknown spacecraft" }}
              <span class="text-text-4">SCID {{ t.scid ?? "not set" }}</span></span
            >
            <span class="min-w-0 truncate font-mono text-sm text-text-3">
              <template v-for="m in t.members" :key="m.request_id"
                >{{ pos(m.position) }} {{ m.command_name ?? m.command_id }} ·
                {{
                  memberStageWord(
                    m.stage,
                    group.state,
                    m.end_reason,
                    t.name,
                    group.release?.expires_at ?? null,
                  )
                }}&ensp;</template
              >
            </span>
            <span class="flex flex-wrap items-center justify-end gap-1.5">
              <!-- E2 (#546): an unattended release refuses this target's waiting uplinks. -->
              <ApTag v-if="t.withdrawn_after_go" state="caution" :label="WITHDRAWN_AFTER_GO_TAG" />
              <ApTag :state="STAGE_STATE[t.stage]" :label="targetStageWord(t, group)" />
            </span>
            <ApButton
              size="compact"
              variant="ghost"
              aria-haspopup="dialog"
              :aria-label="`History of ${t.name ?? 'this target'}`"
              @click="$emit('history', t)"
              >History</ApButton
            >
            <!-- ux C2: a target with its own values shows them on its command line. -->
            <p
              v-for="o in ownOf(t)"
              :key="o.position"
              class="col-span-4 col-start-2 m-0 flex flex-wrap items-center gap-2 font-mono text-sm text-text-2"
            >
              {{ pos(o.position) }} {{ o.name }} {{ o.values }}
              <ApTag state="neutral" label="Own values" />
            </p>
            <!-- ux U69 A4a: verify by / verified at / timed out at, with seconds. -->
            <p
              v-if="targetVerifyTime(t)"
              class="col-span-4 col-start-2 m-0 font-mono text-sm text-text-3"
            >
              {{ targetVerifyTime(t) }}
            </p>
            <p v-if="refusalOf(t)" class="col-span-4 col-start-2 m-0 text-sm text-caution-text">
              {{ refusalOf(t) }}
            </p>
          </li>
        </ul>
        <div
          class="flex flex-wrap items-center gap-3 border-t border-hairline px-4 py-2.5 text-sm text-text-3"
        >
          <span
            >{{ formatCount(page.items.length) }} of {{ formatCount(page.meta.total) }} shown</span
          >
          <ApButton
            size="compact"
            :disabled="pages.moreBusy.value || page.next === null"
            :disabled-reason="pages.moreBusy.value ? 'Loading…' : 'Every target is shown'"
            @click="pages.more"
            >Load more</ApButton
          >
          <!-- It answers the person's own click: an alert, always mounted (a11y B6). -->
          <span role="alert" class="text-caution-text">{{
            pages.moreError.value
              ? `Couldn't load more: ${describeApiError(pages.moreError.value)}`
              : ""
          }}</span>
        </div>
      </template>
    </ApRemote>
  </ApPanel>
</template>
