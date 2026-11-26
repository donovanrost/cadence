# L18 catalog artifact page, reimport, download: shape proposal (fe-setup → api, cc lead)

fe-setup, 2026-11-13. BACKLOG §11 L18. ux `screens/Catalog.md` has no artifact page; this follows the LiveView
`/missions/:id/catalog/artifacts/:artifact_id` (`Reads.Catalog.Artifacts.catalog_artifact_show`) and keeps the
console's catalog patterns (index §A, import run §C).

## What exists (read, 2026-11-13)
- **Artifact:** `Catalog.Artifact` `{artifact_id, catalog_database_id, artifact_name, format_key, format_version,
  media_type, content_sha256, uploaded_by, uploaded_at, metadata}`. The LiveView page shows format, media type,
  upload time, a download link and the import runs made from it (`list_import_runs(artifact_id: …)`).
- **Reimport:** `Catalog.Reimport.execute(scope, mission_id, artifact_id)` (`:operate_mission`) starts a new
  import run on the stored file and returns `{import_run_id}`. Only the LiveView calls it.
- **Download:** `GET /missions/:mission_id/catalog/artifacts/:artifact_id/download`
  (`CatalogArtifactDownloadController`, browser pipeline + `require_authenticated_scope`) sends the bytes with a
  content-disposition. It sits outside the console API, beside the LiveView routes we're deleting.
- The console reads each revision's `artifact {id, file_name, format_label, size_bytes}` (catalog index) and the
  import run's `file {name, format_label, size_bytes}` (C1). Neither has a download link or an artifact id on the
  run.

## Proposed (`/api/v1/missions/:mission_id/catalog`)
### K1 artifact
```
GET /artifacts/:artifact_id → {artifact: {id, file_name, format_label, format_version|null, media_type|null,
                                          size_bytes|null, sha256, uploaded_at, uploaded_by {id, name}|null,
                                          database {id, name}, download_url},
                               revisions:   [{id, number, label|null, imported_at}],     (made from this file)
                               import_runs: [<the catalog index's import run row>],      (newest first, 50)
                               permissions: ["catalog.import"]}
  404 artifact_not_found
```
### K2 reimport
```
POST /artifacts/:artifact_id/reimport → 202 {import_run: {id}}
  404 artifact_not_found · 403 forbidden
  409 import_running {import_run_id}   (a run on this file is still running; the console links to it)
```
- The 409 is an ask: without it two clicks start two runs on the same bytes. Drop it if runs are cheap to
  duplicate.
### K3 download
- Serve it under the console API: `GET /artifacts/:artifact_id/download` (same controller, same auth, plus
  `:operate_mission` / mission membership). It's a plain link, so a session cookie is enough.
- Add `download_url` to the artifact (K1), to the catalog index's `revision.artifact`, and add
  `artifact {id, download_url}` to the import run's `file` (C1), so every place that names the file can link it.

## Console (fe-setup, against fixtures until K1–K3 land)
- Route `setup.catalog.artifact` (`M/setup/catalog/artifacts/:artifactId`), reading layout. Header: lbl
  `EARENDIL · CATALOG · SOURCE FILE`, h1 the file name (mono), subline `XTCE 1.2 · 2.4 MB · uploaded 11-12 by
  Mira K.`. Actions: `Download` (secondary, plain link) and `Import again` (primary, `catalog.import` only).
  `Import again` says first: "Runs the importer on this file again and makes a new candidate revision. Nothing
  changes on spacecraft until you roll it out." Then it goes to the new run (`setup.catalog.import`).
- Panels: **Revisions from this file** (Revision link, Label, Imported) and **Import runs** (the index's row, same
  columns). SHA-256 and database in a `Technical details` disclosure.
- Links in: the Revisions table's Source file cell and the import run's file line link to the artifact page;
  a `Download` link sits beside each.
