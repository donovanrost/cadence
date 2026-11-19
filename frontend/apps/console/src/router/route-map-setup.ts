import type {
  Raw,
  RawOpt,
  InMission,
  AddSpacecraftStep,
  ConfigurationSection,
} from "./route-types.ts";

/** Setup-mode routes (inside a mission). Part of ConsoleRoutes (route-map.ts). */
export interface SetupRoutes {
  "setup.readiness": InMission<"setup.readiness", "/setup">;
  "setup.spacecraft": InMission<"setup.spacecraft", "/setup/spacecraft">;
  "setup.spacecraft.new": InMission<
    "setup.spacecraft.new",
    "/setup/spacecraft/new/:step?",
    { step?: AddSpacecraftStep | null | undefined },
    { step?: AddSpacecraftStep | "" }
  >;
  "setup.spacecraft.one": InMission<
    "setup.spacecraft.one",
    "/setup/spacecraft/:spacecraftId",
    { spacecraftId: Raw },
    { spacecraftId: string }
  >;
  "setup.spacecraft.configuration": InMission<
    "setup.spacecraft.configuration",
    "/setup/spacecraft/:spacecraftId/configuration/:section?",
    { spacecraftId: Raw; section?: ConfigurationSection | null | undefined },
    { spacecraftId: string; section?: ConfigurationSection | "" }
  >;
  "setup.spacecraft.app": InMission<
    "setup.spacecraft.app",
    "/setup/spacecraft/:spacecraftId/apps/:appKey/:surface?",
    { spacecraftId: Raw; appKey: Raw; surface?: RawOpt },
    { spacecraftId: string; appKey: string; surface?: string }
  >;
  "setup.profiles": InMission<"setup.profiles", "/setup/profiles">;
  "setup.profile.new": InMission<"setup.profile.new", "/setup/profiles/new">;
  "setup.profile": InMission<
    "setup.profile",
    "/setup/profiles/:profileId/:section?",
    { profileId: Raw; section?: RawOpt },
    { profileId: string; section?: string }
  >;
  "setup.catalog": InMission<"setup.catalog", "/setup/catalog">;
  "setup.catalog.artifact": InMission<
    "setup.catalog.artifact",
    "/setup/catalog/artifacts/:artifactId",
    { artifactId: Raw },
    { artifactId: string }
  >;
  "setup.catalog.import": InMission<
    "setup.catalog.import",
    "/setup/catalog/import/:importId?",
    { importId?: RawOpt },
    { importId?: string }
  >;
  "setup.catalog.model": InMission<
    "setup.catalog.model",
    "/setup/catalog/models/:revisionId",
    { revisionId: Raw },
    { revisionId: string }
  >;
  "setup.catalog.database": InMission<
    "setup.catalog.database",
    "/setup/catalog/:databaseId",
    { databaseId: Raw },
    { databaseId: string }
  >;
  "setup.changes": InMission<"setup.changes", "/setup/changes">;
  "setup.activation": InMission<
    "setup.activation",
    "/setup/changes/activations/:requestId",
    { requestId: Raw },
    { requestId: string }
  >;
  "setup.revisions": InMission<"setup.revisions", "/setup/revisions">;
  "setup.revisions.compare": InMission<
    "setup.revisions.compare",
    "/setup/revisions/r:from(\\d+)...r:to(\\d+)",
    { from: Raw; to: Raw },
    { from: string; to: string }
  >;
  "setup.revision": InMission<
    "setup.revision",
    "/setup/revisions/:revision(\\d+)",
    { revision: Raw },
    { revision: string }
  >;
  "setup.comms": InMission<"setup.comms", "/setup/comms">;
  "setup.comms.transports": InMission<
    "setup.comms.transports",
    "/setup/comms/transports/:transportId?",
    { transportId?: RawOpt },
    { transportId?: string }
  >;
  "setup.stations": InMission<
    "setup.stations",
    "/setup/stations/:stationId?",
    { stationId?: RawOpt },
    { stationId?: string }
  >;
  "setup.stations.providers": InMission<
    "setup.stations.providers",
    "/setup/stations/providers/:providerId?",
    { providerId?: RawOpt },
    { providerId?: string }
  >;
  "setup.contact-planning": InMission<"setup.contact-planning", "/setup/contact-planning">;
  "setup.contact-planning.policy": InMission<
    "setup.contact-planning.policy",
    "/setup/contact-planning/policy"
  >;
  "setup.contact-planning.requirement": InMission<
    "setup.contact-planning.requirement",
    "/setup/contact-planning/requirements/:requirementId",
    { requirementId: Raw },
    { requirementId: string }
  >;
  "setup.contact-planning.template": InMission<
    "setup.contact-planning.template",
    "/setup/contact-planning/templates/:templateId",
    { templateId: Raw },
    { templateId: string }
  >;
  "setup.data-sources": InMission<
    "setup.data-sources",
    "/setup/data-sources/:sourceId?",
    { sourceId?: RawOpt },
    { sourceId?: string }
  >;
  "setup.apps": InMission<"setup.apps", "/setup/apps">;
  "setup.app": InMission<
    "setup.app",
    "/setup/apps/:appKey/:surface?",
    { appKey: Raw; surface?: RawOpt },
    { appKey: string; surface?: string }
  >;
  "setup.settings": InMission<
    "setup.settings",
    "/setup/settings/:section?",
    { section?: RawOpt },
    { section?: string }
  >;
}
