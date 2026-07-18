#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CADENCE_APP_DIR="$ROOT_DIR/apps/cadence"
STAGE_2_VERSION=20260714020000
STAGE_3_VERSION=20260715050000
STAGE_4_VERSION=20260716040000
RUN_SUFFIX="${USER:-user}_$$"
CLEAN_PARTITION="_stage3_clean_${RUN_SUFFIX}"
UPGRADE_PARTITION="_stage3_upgrade_${RUN_SUFFIX}"

export PGHOST="${PGHOST:-localhost}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"

database_name() {
  printf 'cadence_test%s' "$1"
}

mix_for_partition() {
  local partition="$1"
  shift

  (
    cd "$CADENCE_APP_DIR"
    MIX_ENV=test MIX_TEST_PARTITION="$partition" mix "$@"
  )
}

drop_database() {
  mix_for_partition "$1" ecto.drop --force --quiet >/dev/null 2>&1 || true
}

cleanup() {
  drop_database "$CLEAN_PARTITION"
  drop_database "$UPGRADE_PARTITION"
}

trap cleanup EXIT

run_sql() {
  local partition="$1"
  PGPASSWORD="$PGPASSWORD" psql \
    --host "$PGHOST" \
    --username "$PGUSER" \
    --dbname "$(database_name "$partition")" \
    --set ON_ERROR_STOP=1 \
    --quiet
}

drop_database "$CLEAN_PARTITION"
mix_for_partition "$CLEAN_PARTITION" ecto.create --quiet
mix_for_partition "$CLEAN_PARTITION" ecto.migrate --quiet

run_sql "$CLEAN_PARTITION" <<'SQL'
DO $stage3_clean$
BEGIN
  IF to_regclass('public.provider_accounts') IS NULL
     OR to_regclass('public.provider_account_grants') IS NULL
     OR to_regclass('public.provider_event_inbox') IS NULL
     OR to_regclass('public.provider_reservation_changes') IS NULL
     OR to_regclass('public.scheduled_contact_revisions') IS NULL
     OR to_regclass('public.contact_requirements') IS NULL
     OR to_regclass('public.contact_requirement_versions') IS NULL
     OR to_regclass('public.contact_planning_runs') IS NULL
     OR to_regclass('public.contact_planning_searches') IS NULL
     OR to_regclass('public.contact_opportunity_snapshots') IS NULL
     OR to_regclass('public.contact_plans') IS NULL
     OR to_regclass('public.contact_plan_versions') IS NULL
     OR to_regclass('public.contact_plan_approvals') IS NULL
     OR to_regclass('public.contact_plan_execution_items') IS NULL
     OR to_regclass('public.contact_requirement_templates') IS NULL
     OR to_regclass('public.contact_requirement_template_versions') IS NULL
     OR to_regclass('public.contact_requirement_occurrences') IS NULL
     OR to_regclass('public.fleet_planning_policies') IS NULL
     OR to_regclass('public.fleet_planning_policy_versions') IS NULL
     OR to_regclass('public.fleet_planning_policy_approvals') IS NULL
     OR to_regclass('public.fleet_planning_runs') IS NULL
     OR to_regclass('public.fleet_planning_run_requirement_refs') IS NULL
     OR to_regclass('public.fleet_planning_decisions') IS NULL
     OR to_regclass('public.automation_grants') IS NULL
     OR to_regclass('public.fleet_automation_actions') IS NULL THEN
    RAISE EXCEPTION 'clean migration did not create the complete Stage 3 through Stage 5 schema';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_constraint
    WHERE conname IN (
      'contact_requirements_current_version_fk',
      'contact_planning_runs_requirement_version_fk',
      'contact_opportunity_snapshots_requirement_version_fk',
      'contact_plans_current_version_fk',
      'contact_plans_approved_version_fk',
      'contact_plan_execution_items_plan_version_fk',
      'contact_plan_execution_items_snapshot_fk',
      'contact_plan_execution_items_reservation_fk',
      'provider_reservations_contact_requirement_fk',
      'provider_reservations_contact_plan_fk',
      'provider_reservations_opportunity_snapshot_fk'
    ) AND contype = 'f' AND convalidated
  ) <> 11 THEN
    RAISE EXCEPTION 'clean Stage 4 migration did not create every validated exact reference';
  END IF;

  IF (
    SELECT count(*)
    FROM pg_constraint
    WHERE conname IN (
      'contact_requirement_templates_mission_fk',
      'contact_requirement_template_versions_template_fk',
      'contact_requirement_template_versions_spacecraft_fk',
      'contact_requirement_templates_current_version_fk',
      'contact_requirement_occurrences_template_version_fk',
      'contact_requirement_occurrences_requirement_version_fk',
      'fleet_planning_policies_mission_fk',
      'fleet_planning_policy_versions_policy_fk',
      'fleet_planning_policies_current_version_fk',
      'fleet_planning_policies_active_version_fk',
      'fleet_planning_policy_approvals_version_fk',
      'fleet_planning_runs_policy_version_fk',
      'fleet_planning_runs_source_run_fk',
      'fleet_planning_runs_source_plan_fk',
      'fleet_planning_runs_candidate_plan_fk',
      'fleet_planning_run_requirement_refs_run_fk',
      'fleet_planning_run_requirement_refs_requirement_fk',
      'fleet_planning_run_requirement_refs_planning_run_fk',
      'fleet_planning_decisions_run_fk',
      'fleet_planning_decisions_snapshot_fk',
      'automation_grants_mission_fk',
      'automation_grants_service_identity_fk',
      'automation_grants_policy_version_fk',
      'contact_plan_approvals_automation_grant_fk',
      'fleet_automation_actions_grant_fk',
      'fleet_automation_actions_run_fk',
      'fleet_automation_actions_plan_fk'
    ) AND contype = 'f' AND convalidated
  ) <> 27 THEN
    RAISE EXCEPTION 'clean Stage 5 migration did not create every validated exact reference';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'contact_plan_versions'
      AND column_name = 'locked_snapshot_ids'
      AND is_nullable = 'NO'
  ) THEN
    RAISE EXCEPTION 'clean Stage 5 migration is missing locked Plan commitments';
  END IF;
END
$stage3_clean$;
SQL

drop_database "$UPGRADE_PARTITION"
mix_for_partition "$UPGRADE_PARTITION" ecto.create --quiet
mix_for_partition "$UPGRADE_PARTITION" ecto.migrate --to "$STAGE_2_VERSION" --quiet

run_sql "$UPGRADE_PARTITION" <<'SQL'
INSERT INTO organizations (
  organization_id, slug, display_name, metadata, inserted_at
) VALUES (
  'org-stage3-upgrade', 'stage3-upgrade', 'Stage 3 Upgrade Audit', '{}',
  '2026-07-14 00:00:00'
);

INSERT INTO missions (
  mission_id, organization_id, slug, display_name, metadata, inserted_at
) VALUES (
  'mission-stage3-upgrade', 'org-stage3-upgrade', 'upgrade-mission',
  'Upgrade Mission', '{}', '2026-07-14 00:00:00'
);

INSERT INTO scheduled_contacts (
  scheduled_contact_id, organization_id, mission_id, source_endpoint_refs,
  path_documents, starts_at, ends_at, provider_contact_ref, lifecycle_state,
  metadata, path_template_ids, path_template_ref_documents,
  link_assignment_ref_documents, contact_intents, inserted_at
) VALUES
  (
    'scheduled-stage2-one', 'org-stage3-upgrade', 'mission-stage3-upgrade',
    ARRAY['source-one'], '{"path":"one"}', '2026-07-16 01:00:00',
    '2026-07-16 01:10:00', 'provider-contact-one', 'scheduled',
    '{"fixture":"stage2"}', ARRAY['path-one'], '{"items":[]}',
    '{"items":[]}', ARRAY['telemetry'], '2026-07-14 01:00:00'
  ),
  (
    'scheduled-stage2-two', 'org-stage3-upgrade', 'mission-stage3-upgrade',
    ARRAY['source-two'], '{"path":"two"}', '2026-07-16 02:00:00',
    '2026-07-16 02:12:00', 'provider-contact-two', 'scheduled',
    '{"fixture":"stage2"}', ARRAY['path-two'], '{"items":[]}',
    '{"items":[]}', ARRAY['tracking'], '2026-07-14 02:00:00'
  ),
  (
    'scheduled-stage2-three', 'org-stage3-upgrade', 'mission-stage3-upgrade',
    ARRAY['source-three'], '{"path":"three"}', '2026-07-16 03:00:00',
    '2026-07-16 03:15:00', 'provider-contact-three', 'completed',
    '{"fixture":"stage2"}', ARRAY['path-three'], '{"items":[]}',
    '{"items":[]}', ARRAY['telemetry'], '2026-07-14 03:00:00'
  );

INSERT INTO mission_providers (
  provider_id, organization_id, mission_id, version, lifecycle_state,
  display_name, provider_type, client_key, base_url, credential_ref,
  environment_ref, capabilities_document, inventory_sync_document, metadata,
  inserted_at, updated_at
) VALUES
  (
    'provider-stage2-alpha', 'org-stage3-upgrade', 'mission-stage3-upgrade', 1,
    'archived', 'Simulator Alpha v1', 'simulator', 'simulator_http',
    'http://simulator-alpha-v1.test', 'env://SIMULATOR_ALPHA_V1', 'run-alpha-v1',
    '{"contact_modification":false}', '{"revision":1}',
    '{"fixture":"stage2"}', '2026-07-14 01:00:00', '2026-07-14 01:00:00'
  ),
  (
    'provider-stage2-alpha', 'org-stage3-upgrade', 'mission-stage3-upgrade', 2,
    'active', 'Simulator Alpha v2', 'simulator', 'simulator_http',
    'http://simulator-alpha-v2.test', 'env://SIMULATOR_ALPHA_V2', 'run-alpha-v2',
    '{"contact_modification":true}', '{"revision":2}',
    '{"fixture":"stage2"}', '2026-07-14 02:00:00', '2026-07-14 02:00:00'
  ),
  (
    'provider-stage2-beta', 'org-stage3-upgrade', 'mission-stage3-upgrade', 1,
    'active', 'Simulator Beta v1', 'simulator', 'simulator_http',
    'http://simulator-beta-v1.test', 'env://SIMULATOR_BETA_V1', 'run-beta-v1',
    '{"event_polling":true}', '{"revision":1}',
    '{"fixture":"stage2"}', '2026-07-14 03:00:00', '2026-07-14 03:00:00'
  );

INSERT INTO provider_reservations (
  provider_reservation_id, organization_id, mission_id, provider_profile_id,
  provider_profile_version, scheduled_contact_id, provider_opportunity_ref,
  provider_contact_ref, idempotency_key, lifecycle_state, provider_status,
  spacecraft_id, provider_spacecraft_ref, source_endpoint_refs,
  path_template_ids, starts_at, ends_at, request_document, response_document,
  metadata, inserted_at, updated_at, provider_id, provider_version,
  service_profile_ref, delivery_profile_ref, delivery_descriptor_document
) VALUES
  (
    'reservation-stage2-one', 'org-stage3-upgrade', 'mission-stage3-upgrade',
    'runtime-profile-one', 1, 'scheduled-stage2-one', 'opportunity-one',
    'provider-contact-one', 'idempotency-one', 'confirmed', 'confirmed',
    'spacecraft-one', 'SC-001', ARRAY['source-one'], ARRAY['path-one'],
    '2026-07-16 01:00:00', '2026-07-16 01:10:00',
    '{"provider_request":{"starts_at":"2026-07-16T01:00:00Z","ends_at":"2026-07-16T01:10:00Z"}}',
    '{}', '{"fixture":"stage2"}', '2026-07-14 01:00:00',
    '2026-07-14 01:00:00', 'provider-stage2-alpha', 1,
    '{"id":"service-one","version":1}', '{"id":"delivery-one","version":1}',
    '{"protocol":"tcp"}'
  ),
  (
    'reservation-stage2-two', 'org-stage3-upgrade', 'mission-stage3-upgrade',
    'runtime-profile-two', 1, 'scheduled-stage2-two', 'opportunity-two',
    'provider-contact-two', 'idempotency-two', 'confirmed', 'confirmed',
    'spacecraft-two', 'SC-002', ARRAY['source-two'], ARRAY['path-two'],
    '2026-07-16 02:00:00', '2026-07-16 02:12:00',
    '{"provider_request":{"starts_at":"2026-07-16T02:00:00Z","ends_at":"2026-07-16T02:12:00Z"}}',
    '{"provider_revision":"4","starts_at":"2026-07-16T02:01:00Z","ends_at":"2026-07-16T02:13:00Z"}',
    '{"fixture":"stage2"}', '2026-07-14 02:00:00',
    '2026-07-14 02:00:00', 'provider-stage2-alpha', 2,
    '{"id":"service-two","version":2}', '{"id":"delivery-two","version":2}',
    '{"protocol":"tcp"}'
  ),
  (
    'reservation-stage2-three', 'org-stage3-upgrade', 'mission-stage3-upgrade',
    'runtime-profile-three', 1, 'scheduled-stage2-three', 'opportunity-three',
    'provider-contact-three', 'idempotency-three', 'completed', 'completed',
    'spacecraft-three', 'SC-003', ARRAY['source-three'], ARRAY['path-three'],
    '2026-07-16 03:00:00', '2026-07-16 03:15:00',
    '{"provider_request":{"starts_at":"2026-07-16T03:00:00Z","ends_at":"2026-07-16T03:15:00Z"}}',
    '{"provider_revision":"not-a-number","status":"completed"}',
    '{"fixture":"stage2"}', '2026-07-14 03:00:00',
    '2026-07-14 03:00:00', 'provider-stage2-beta', 1,
    '{"id":"service-three","version":1}', '{"id":"delivery-three","version":1}',
    '{"protocol":"tcp"}'
  );
SQL

mix_for_partition "$UPGRADE_PARTITION" ecto.migrate --to "$STAGE_3_VERSION" --quiet

run_sql "$UPGRADE_PARTITION" <<'SQL'
DO $stage3_upgrade$
BEGIN
  IF (SELECT count(*) FROM mission_providers) <> 3
     OR (SELECT count(*) FROM provider_reservations) <> 3
     OR (SELECT count(*) FROM scheduled_contacts) <> 3
     OR (SELECT count(*) FROM provider_accounts) <> 2
     OR (SELECT count(*) FROM provider_account_versions) <> 3
     OR (SELECT count(*) FROM provider_account_grants) <> 3
     OR (SELECT count(*) FROM scheduled_contact_revisions) <> 3 THEN
    RAISE EXCEPTION 'Stage 2 fixture or Stage 3 backfill cardinality changed during upgrade';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM mission_providers AS provider
    LEFT JOIN provider_accounts AS account
      ON account.organization_id = provider.organization_id
      AND account.provider_account_id = provider.provider_account_id
    LEFT JOIN provider_account_versions AS account_version
      ON account_version.organization_id = provider.organization_id
      AND account_version.provider_account_id = provider.provider_account_id
      AND account_version.version = provider.provider_account_version
    LEFT JOIN provider_account_grants AS grant_row
      ON grant_row.organization_id = provider.organization_id
      AND grant_row.mission_id = provider.mission_id
      AND grant_row.provider_account_grant_id = provider.provider_account_grant_id
      AND grant_row.version = provider.provider_account_grant_version
    WHERE provider.provider_account_id <>
            'legacy_provider_account_' || md5(
              provider.organization_id || ':' || provider.mission_id || ':' || provider.provider_id
            )
       OR provider.provider_account_grant_id <>
            'legacy_provider_grant_' || md5(
              provider.organization_id || ':' || provider.mission_id || ':' || provider.provider_id
            )
       OR provider.provider_account_version <> provider.version
       OR provider.provider_account_grant_version <> provider.version
       OR account.provider_account_id IS NULL
       OR account.active_version <> (
            SELECT max(historical.version)
            FROM mission_providers AS historical
            WHERE historical.organization_id = provider.organization_id
              AND historical.mission_id = provider.mission_id
              AND historical.provider_id = provider.provider_id
          )
       OR account_version.provider_account_id IS NULL
       OR account_version.base_url <> provider.base_url
       OR account_version.environment_ref <> provider.environment_ref
       OR account_version.credential_ref <> provider.credential_ref
       OR grant_row.provider_account_grant_id IS NULL
       OR grant_row.provider_account_version <> provider.version
       OR grant_row.lifecycle_state <>
            CASE WHEN provider.lifecycle_state = 'archived' THEN 'revoked' ELSE 'active' END
       OR provider.delivery_policy_document <> '{}'::jsonb
  ) THEN
    RAISE EXCEPTION 'historical Mission Provider account, grant, or policy binding is not exact';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM provider_reservations AS reservation
    LEFT JOIN mission_providers AS provider
      ON provider.organization_id = reservation.organization_id
      AND provider.mission_id = reservation.mission_id
      AND provider.provider_id = reservation.provider_id
      AND provider.version = reservation.provider_version
    WHERE provider.provider_id IS NULL
       OR reservation.provider_account_id <> provider.provider_account_id
       OR reservation.provider_account_version <> provider.provider_account_version
       OR reservation.provider_account_grant_id <> provider.provider_account_grant_id
       OR reservation.provider_account_grant_version <> provider.provider_account_grant_version
       OR provider.delivery_policy_document <> '{}'::jsonb
       OR reservation.provider_revision <> CASE
            WHEN reservation.response_document->>'provider_revision' ~ '^[1-9][0-9]*$'
              THEN (reservation.response_document->>'provider_revision')::integer
            ELSE 1
          END
       OR reservation.requested_snapshot_document <>
            COALESCE(
              reservation.request_document->'provider_request',
              reservation.request_document,
              '{}'::jsonb
            )
       OR reservation.provider_confirmed_snapshot_document <> CASE
            WHEN reservation.response_document = '{}'::jsonb
              THEN COALESCE(
                reservation.request_document->'provider_request',
                reservation.request_document,
                '{}'::jsonb
              )
            ELSE reservation.response_document
          END
       OR reservation.cadence_accepted_snapshot_document <>
            reservation.provider_confirmed_snapshot_document
  ) THEN
    RAISE EXCEPTION 'historical Provider Reservation ownership, policy, or truth snapshots are not exact';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM scheduled_contacts AS contact
    LEFT JOIN scheduled_contact_revisions AS revision
      ON revision.scheduled_contact_id = contact.scheduled_contact_id
      AND revision.revision = 1
    WHERE contact.current_revision <> 1
       OR revision.scheduled_contact_revision_id IS NULL
       OR revision.organization_id <> contact.organization_id
       OR revision.mission_id <> contact.mission_id
       OR revision.snapshot_document <> jsonb_build_object(
            'starts_at', contact.starts_at,
            'ends_at', contact.ends_at,
            'provider_contact_ref', contact.provider_contact_ref,
            'source_endpoint_refs', contact.source_endpoint_refs,
            'path_template_ids', contact.path_template_ids,
            'lifecycle_state', contact.lifecycle_state,
            'metadata', contact.metadata
          )
       OR revision.reason_document <> '{"kind":"stage_3_backfill"}'::jsonb
       OR revision.created_by <> 'stage_3_migration'
  ) THEN
    RAISE EXCEPTION 'historical Scheduled Contact revision backfill is not exact';
  END IF;

  IF EXISTS (
    SELECT scheduled_contact_id
    FROM scheduled_contact_revisions
    GROUP BY scheduled_contact_id
    HAVING count(*) <> 1
  ) THEN
    RAISE EXCEPTION 'historical Scheduled Contact has duplicate backfilled revisions';
  END IF;
END
$stage3_upgrade$;
SQL

mix_for_partition "$UPGRADE_PARTITION" ecto.migrate --to "$STAGE_4_VERSION" --quiet

run_sql "$UPGRADE_PARTITION" <<'SQL'
BEGIN;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO mission_spacecraft (
  spacecraft_id, organization_id, mission_id, display_name, metadata,
  inserted_at
) VALUES (
  'spacecraft-stage4-upgrade', 'org-stage3-upgrade', 'mission-stage3-upgrade',
  'Stage 4 Upgrade Spacecraft', '{"fixture":"stage4"}',
  '2026-07-16 00:00:00'
);

INSERT INTO contact_requirements (
  contact_requirement_id, organization_id, mission_id, current_version,
  lifecycle_state, created_by, lifecycle_changed_by, lifecycle_changed_at,
  lifecycle_reason, inserted_at, updated_at
) VALUES (
  'requirement-stage4-upgrade', 'org-stage3-upgrade', 'mission-stage3-upgrade',
  1, 'active', 'stage4-migration', 'stage4-migration',
  '2026-07-16 00:00:00', '', '2026-07-16 00:00:00',
  '2026-07-16 00:00:00'
);

INSERT INTO contact_requirement_versions (
  contact_requirement_version_id, contact_requirement_id, organization_id,
  mission_id, version, spacecraft_id, service_direction, contact_intent,
  earliest_start, latest_end, success_measure, minimum_duration_seconds,
  preferred_duration_seconds, minimum_data_volume_bytes, contact_count,
  minimum_separation_seconds, priority, provider_constraints_document,
  station_constraints_document, policy_constraints_document,
  approval_policy_document, rationale, metadata, content_sha256, created_by,
  created_at
) VALUES (
  'requirement-stage4-upgrade-v1', 'requirement-stage4-upgrade',
  'org-stage3-upgrade', 'mission-stage3-upgrade', 1,
  'spacecraft-stage4-upgrade', 'downlink', 'stage4_upgrade_contact',
  '2026-07-18 00:00:00', '2026-07-18 01:00:00', 'minimum_duration',
  300, 600, NULL, 1, 0, 'high', '{"allowed":[],"excluded":[]}',
  '{"allowed":[],"excluded":[]}', '{}', '{"mode":"manual"}',
  'Retained Stage 4 Requirement', '{"fixture":"stage4"}',
  'stage4-requirement-content-hash', 'stage4-migration',
  '2026-07-16 00:00:00'
);

INSERT INTO contact_plans (
  contact_plan_id, organization_id, mission_id, current_version,
  lifecycle_state, created_by, lifecycle_changed_by, lifecycle_changed_at,
  lifecycle_reason, approved_version, approved_at, approved_by, inserted_at,
  updated_at
) VALUES (
  'plan-stage4-upgrade', 'org-stage3-upgrade', 'mission-stage3-upgrade', 1,
  'draft', 'stage4-migration', 'stage4-migration', '2026-07-16 00:00:00',
  '', NULL, NULL, NULL, '2026-07-16 00:00:00', '2026-07-16 00:00:00'
);

INSERT INTO contact_plan_versions (
  contact_plan_version_id, contact_plan_id, organization_id, mission_id,
  version, requirement_refs_document, planning_run_refs_document,
  selected_snapshot_ids, rejected_snapshot_ids, coverage_document,
  conflict_document, unsatisfied_document, policy_snapshot_document, rationale,
  content_sha256, created_by, created_at
) VALUES (
  'plan-stage4-upgrade-v1', 'plan-stage4-upgrade', 'org-stage3-upgrade',
  'mission-stage3-upgrade', 1,
  '{"requirements":[{"id":"requirement-stage4-upgrade","version":1}]}',
  '{"runs":[]}', ARRAY[]::varchar[], ARRAY[]::varchar[],
  '{"satisfied":false}', '{"clear":true}', '{"requirements":[]}', '{}',
  'Retained Stage 4 Plan', 'stage4-plan-content-hash', 'stage4-migration',
  '2026-07-16 00:00:00'
);

COMMIT;
SQL

mix_for_partition "$UPGRADE_PARTITION" ecto.migrate --quiet

run_sql "$UPGRADE_PARTITION" <<'SQL'
DO $stage5_upgrade$
BEGIN
  IF (SELECT count(*) FROM provider_reservations) <> 3
     OR (SELECT count(*) FROM scheduled_contacts) <> 3
     OR (SELECT count(*) FROM contact_requirements) <> 1
     OR (SELECT count(*) FROM contact_requirement_versions) <> 1
     OR (SELECT count(*) FROM contact_plans) <> 1
     OR (SELECT count(*) FROM contact_plan_versions) <> 1 THEN
    RAISE EXCEPTION 'populated Stage 3 and Stage 4 records changed during Stage 5 upgrade';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM provider_reservations
    WHERE contact_requirement_id IS NOT NULL
       OR contact_requirement_version IS NOT NULL
       OR contact_plan_id IS NOT NULL
       OR contact_plan_version IS NOT NULL
       OR contact_opportunity_snapshot_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'existing direct reservations acquired synthetic planning references';
  END IF;

  IF to_regclass('public.contact_requirement_templates') IS NULL
     OR to_regclass('public.contact_requirement_occurrences') IS NULL
     OR to_regclass('public.fleet_planning_policies') IS NULL
     OR to_regclass('public.fleet_planning_runs') IS NULL
     OR to_regclass('public.fleet_planning_decisions') IS NULL
     OR to_regclass('public.automation_grants') IS NULL
     OR to_regclass('public.fleet_automation_actions') IS NULL THEN
    RAISE EXCEPTION 'populated Stage 4 upgrade did not create the complete Stage 5 schema';
  END IF;

  IF (SELECT locked_snapshot_ids FROM contact_plan_versions
      WHERE contact_plan_id = 'plan-stage4-upgrade') <> ARRAY[]::varchar[] THEN
    RAISE EXCEPTION 'historical Stage 4 Plan acquired synthetic locked commitments';
  END IF;

  IF EXISTS (SELECT 1 FROM fleet_planning_runs)
     OR EXISTS (SELECT 1 FROM fleet_planning_run_requirement_refs)
     OR EXISTS (SELECT 1 FROM fleet_planning_decisions)
     OR EXISTS (SELECT 1 FROM fleet_automation_actions) THEN
    RAISE EXCEPTION 'historical Stage 4 records acquired synthetic Stage 5 fleet references';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM contact_requirements
    WHERE contact_requirement_id = 'requirement-stage4-upgrade'
      AND current_version = 1
      AND lifecycle_state = 'active'
  ) OR NOT EXISTS (
    SELECT 1 FROM contact_plans
    WHERE contact_plan_id = 'plan-stage4-upgrade'
      AND current_version = 1
      AND lifecycle_state = 'draft'
  ) THEN
    RAISE EXCEPTION 'historical Stage 4 Requirement or Plan content was not retained';
  END IF;
END
$stage5_upgrade$;
SQL

printf 'Stage 3 provider, Stage 4 planning, and Stage 5 fleet migration audit passed (clean database and populated Stage 4 upgrade).\n'
