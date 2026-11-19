# catalog-import: accessibility (§6)

Owner: fe-setup. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- **Kit (lead):** at 390 the table wrapper `div.overflow-x-auto` scrolls sideways but has no tab stop, role or name, so keyboard users can't scroll it (axe `scrollable-region-focusable`, serious). One kit fix covers every table: `tabindex="0"`, `role="region"` and an `aria-label` naming the table. Seen on the import run page.

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `M/setup/catalog/import` | member | 1440 | ok | 1 | 22 | none |
| `M/setup/catalog/import` | member | 390 | ok | 1 | 9 | none |
| `M/setup/catalog/import` | admin | 1440 | ok | 1 | 27 | none |
| `M/setup/catalog/import` | admin | 390 | ok | 1 | 9 | none |
| `M/setup/catalog/import/catalog_import_run_ieeplt7lvu_2LQPG` | member | 1440 | ok | 1 | 19 | none |
| `M/setup/catalog/import/catalog_import_run_ieeplt7lvu_2LQPG` | member | 390 | ok | 1 | 7 | scrollable-region-focusable (serious, 1) |
| `M/setup/catalog/import/catalog_import_run_ieeplt7lvu_2LQPG` | admin | 1440 | ok | 1 | 28 | none |
| `M/setup/catalog/import/catalog_import_run_ieeplt7lvu_2LQPG` | admin | 390 | ok | 1 | 10 | scrollable-region-focusable (serious, 1) |
