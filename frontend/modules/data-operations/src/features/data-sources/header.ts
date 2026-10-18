import type { ComputedRef, Ref } from "vue";
import { useOpsHeaders } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";
import type { SourceModel } from "./native-contract";

const list = "/missions/:mission_id/ops/data-sources";
const source = "/missions/:mission_id/ops/data-sources/:data_source_id";

/** Headers for every Data Sources route this component serves. */
export function useSourcesHeader(
  model: ComputedRef<SourceModel>,
  refresh: () => unknown,
  pending: Ref<boolean>,
) {
  const mission = () => ({ mission_id: model.value.context.mission_id });
  const selected = () => model.value.selected?.source;
  const title = () => selected()?.logical_source ?? selected()?.id ?? "Data source";
  const sourceParams = () => ({ ...mission(), data_source_id: selected()?.id ?? "" });
  const run = { run: async () => void (await refresh()), pending: pending.value };
  const allSources = () =>
    ({
      id: "all-sources",
      label: "All sources",
      icon: "hero-arrow-uturn-left",
      href: href(list, mission()),
    }) as const;

  useOpsHeaders({
    [list]: () => ({
      description:
        "Inspect source configuration, binding history and observed telemetry before changing a backend.",
      ...(model.value.permissions.manage
        ? {
            primary: {
              id: "register",
              label: "Register source",
              icon: "hero-plus",
              href: href("/missions/:mission_id/ops/data-sources/registration/new", mission()),
            },
          }
        : {}),
      refresh: { ...run, pending: pending.value },
    }),
    [source]: () => ({
      title: title(),
      actions: model.value.permissions.manage
        ? [
            allSources(),
            {
              id: "settings",
              label: "Settings",
              icon: "hero-cog-6-tooth",
              href: href(
                "/missions/:mission_id/ops/data-sources/:data_source_id/settings",
                sourceParams(),
              ),
            },
          ]
        : [allSources()],
      refresh: { ...run, pending: pending.value },
    }),
    "/missions/:mission_id/ops/data-sources/registration/new": () => ({
      description:
        "Register a source and review the binding it creates before it receives telemetry.",
      actions: [allSources()],
      refresh: { ...run, pending: pending.value },
    }),
    "/missions/:mission_id/ops/data-sources/:data_source_id/settings": () => ({
      title: title(),
      actions: [
        {
          id: "source",
          label: "Back to source",
          icon: "hero-arrow-uturn-left",
          href: href(source, sourceParams()),
        },
      ],
      refresh: { ...run, pending: pending.value },
    }),
  });
}
