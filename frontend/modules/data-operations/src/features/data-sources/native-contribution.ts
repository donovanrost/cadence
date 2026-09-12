import type { Component } from "vue";
import type { OpsPageContribution } from "@cadence/plugin-sdk/ops-pages";
import NativeDataSources from "./NativeDataSources.vue";
import { admitSourcePage, sourceActions } from "./native-contract";
export const sourceContributions: OpsPageContribution<Component>[] = [
  ["sources", "reader"],
  ["source", "reader"],
  ["source-registration", "registration"],
  ["source-settings", "settings"],
].map(([name, mode]) => ({
  id: `data-operations.${name}`,
  slot: "ops.page",
  version: 1,
  title: "Data Sources",
  component: NativeDataSources,
  query: true,
  actions: sourceActions,
  read(value, context) {
    const page = admitSourcePage(
      value,
      { organization_id: context.organizationId, mission_id: context.missionId },
      mode,
    );
    if (!page || (name === "source" && !page.model.selected))
      throw Error("Source evidence is unavailable");
    return { page };
  },
}));
