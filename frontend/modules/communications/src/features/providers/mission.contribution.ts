import type { Component } from "vue";
import { MISSION_PAGE_SLOT, type MissionPageContribution } from "@cadence/plugin-sdk/mission-pages";
import CommsProviderList from "./CommsProviderList.vue";
import MissionProviderCreation from "./MissionProviderCreation.vue";
import MissionProviderDetail from "./MissionProviderDetail.vue";
import { readList, readDetail } from "./read-validation";
import { readForm } from "./form-validation";
import { providerPageEnvelope } from "./mission-provider-port";
export const missionPages = [
  {
    id: "comms.provider-list",
    slot: MISSION_PAGE_SLOT,
    version: 1,
    title: "Providers",
    component: CommsProviderList,
    read(value, context) {
      if (context.resourceId !== undefined) throw new Error("Unexpected resource.");
      return readList(value, context);
    },
  },
  {
    id: "comms.provider-new",
    slot: MISSION_PAGE_SLOT,
    version: 1,
    title: "New Provider",
    component: MissionProviderCreation,
    actions: ["create-provider"],
    read(value, context) {
      if (context.resourceId !== undefined) throw new Error("Unexpected resource.");
      const { model, sequence, phase } = providerPageEnvelope(value);
      return {
        model: readForm(model, context),
        context: { missionId: context.missionId },
        sequence,
        phase,
      };
    },
  },
  {
    id: "comms.provider-show",
    slot: MISSION_PAGE_SLOT,
    version: 1,
    title: "Provider",
    component: MissionProviderDetail,
    actions: ["validate-provider", "sync-provider", "archive-provider", "refresh"],
    read(value, context) {
      const { model, sequence, phase } = providerPageEnvelope(value),
        admitted = readDetail(model, context);
      if (!context.resourceId || admitted.provider.provider_id !== context.resourceId)
        throw new Error("Invalid resource.");
      return { model: admitted, context: { missionId: context.missionId }, sequence, phase };
    },
  },
] as const satisfies readonly MissionPageContribution<Component>[];
