import type { Component } from "vue";
import {
  CatalogIndex,
  CatalogDatabaseNew,
  CatalogDatabaseShow,
  CatalogRevisionShow,
  CatalogArtifactShowPage,
  CatalogImportRunShow,
} from "./index";
import {
  assertDatabaseIndex,
  assertDatabaseNew,
  assertDatabaseShow,
} from "./features/databases/validation.ts";
import { assertRevision } from "./features/revisions/validation.ts";
import { assertArtifact } from "./features/artifacts/validation.ts";
import { assertImportRun } from "./features/imports/validation.ts";

// Compiled core pages, not a release catalog or remotely selected import path.
export const catalogPages: Record<
  string,
  { component: Component; validate: (value: unknown) => void }
> = {
  catalog_index: { component: CatalogIndex, validate: assertDatabaseIndex },
  catalog_database_new: { component: CatalogDatabaseNew, validate: assertDatabaseNew },
  catalog_database_show: { component: CatalogDatabaseShow, validate: assertDatabaseShow },
  catalog_revision_show: { component: CatalogRevisionShow, validate: assertRevision },
  catalog_artifact_show: { component: CatalogArtifactShowPage, validate: assertArtifact },
  catalog_import_run_show: { component: CatalogImportRunShow, validate: assertImportRun },
};
