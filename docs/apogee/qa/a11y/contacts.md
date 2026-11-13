# contacts: accessibility (§6)

Owner: fe-ops. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- The drawer was opened with a `scheduled_contact_…` id; the screen asks `GET /passes/<id>` and gets 404. Real links use `provider_reservation_…` ids (the U31 callout does), so this isn't a product bug.

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `M/contacts` | member | 1440 | ok | 1 | 23 | none |
| `M/contacts` | member | 390 | ok | 1 | 16 | none |
| `M/contacts` | admin | 1440 | ok | 1 | 24 | none |
| `M/contacts` | admin | 390 | ok | 1 | 16 | none |
| `M/contacts/scheduled_contact_brs6fn2wcu_39GI9` | member | 1440 | ok | 1 | 23 | none |
| `M/contacts/scheduled_contact_brs6fn2wcu_39GI9` | member | 390 | ok | 1 | 16 | none |
| `M/contacts/scheduled_contact_brs6fn2wcu_39GI9` | admin | 1440 | ok | 1 | 24 | none |
| `M/contacts/scheduled_contact_brs6fn2wcu_39GI9` | admin | 390 | ok | 1 | 16 | none |
