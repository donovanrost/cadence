# contact-planning: accessibility (§6)

Owner: fe-setup. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- **Server (api):** the requirements list read returns 500 for everyone: qa #53 (`String.to_existing_atom("one_off")`). The page shows an error panel where the list goes. Re-check after the fix.

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `M/setup/contact-planning` | member | 1440 | ok | 1 | 31 | none |
| `M/setup/contact-planning` | member | 390 | ok | 1 | 17 | none |
| `M/setup/contact-planning` | admin | 1440 | ok | 1 | 38 | none |
| `M/setup/contact-planning` | admin | 390 | ok | 1 | 19 | none |
| `M/setup/contact-planning/policy` | member | 1440 | ok | 1 | 32 | none |
| `M/setup/contact-planning/policy` | member | 390 | ok | 1 | 18 | none |
| `M/setup/contact-planning/policy` | admin | 1440 | ok | 1 | 40 | none |
| `M/setup/contact-planning/policy` | admin | 390 | ok | 1 | 21 | none |
| `M/setup/contact-planning/templates/contact_requirement_template_phouvt4y5m_I` | member | 1440 | ok | 1 | 17 | none |
| `M/setup/contact-planning/templates/contact_requirement_template_phouvt4y5m_I` | member | 390 | ok | 1 | 4 | none |
| `M/setup/contact-planning/templates/contact_requirement_template_phouvt4y5m_I` | admin | 1440 | ok | 1 | 25 | none |
| `M/setup/contact-planning/templates/contact_requirement_template_phouvt4y5m_I` | admin | 390 | ok | 1 | 7 | none |
