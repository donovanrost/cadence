defmodule Cadence.Repo.Migrations.BindMissionProvidersToAccounts do
  use Ecto.Migration

  def up do
    alter table(:mission_providers) do
      add(:provider_account_id, :string)
      add(:provider_account_version, :integer)
      add(:provider_account_grant_id, :string)
      add(:provider_account_grant_version, :integer)
      add(:delivery_policy_document, :map, null: false, default: %{})
      add(:spacecraft_mappings_document, :map, null: false, default: %{})
      add(:enabled_service_profile_refs, :map, null: false, default: %{"items" => []})
      add(:enabled_delivery_profile_refs, :map, null: false, default: %{"items" => []})
      add(:permitted_resource_refs, {:array, :string}, null: false, default: [])
      add(:preferred_transport_refs, :map, null: false, default: %{"items" => []})
      add(:scheduling_policy_document, :map, null: false, default: %{})
      add(:fallback_policy_document, :map, null: false, default: %{})
    end

    alter table(:provider_reservations) do
      add(:provider_account_id, :string)
      add(:provider_account_version, :integer)
      add(:provider_account_grant_id, :string)
      add(:provider_account_grant_version, :integer)
      add(:operator_review_document, :map, null: false, default: %{})
    end

    flush()
    backfill_accounts()
    backfill_account_versions()
    backfill_grants()
    bind_mission_providers()
    bind_reservations()
    validate_backfill()
    add_binding_constraints()
  end

  def down do
    drop_binding_constraints()

    alter table(:provider_reservations) do
      remove(:operator_review_document)
      remove(:provider_account_grant_version)
      remove(:provider_account_grant_id)
      remove(:provider_account_version)
      remove(:provider_account_id)
    end

    alter table(:mission_providers) do
      remove(:fallback_policy_document)
      remove(:scheduling_policy_document)
      remove(:preferred_transport_refs)
      remove(:permitted_resource_refs)
      remove(:enabled_delivery_profile_refs)
      remove(:enabled_service_profile_refs)
      remove(:spacecraft_mappings_document)
      remove(:delivery_policy_document)
      remove(:provider_account_grant_version)
      remove(:provider_account_grant_id)
      remove(:provider_account_version)
      remove(:provider_account_id)
    end
  end

  defp backfill_accounts do
    execute("""
    INSERT INTO provider_accounts (
      provider_account_id, organization_id, display_name, lifecycle_state,
      active_version, credential_status, event_ingestion_status, metadata,
      inserted_at, updated_at
    )
    SELECT
      'legacy_provider_account_' || md5(organization_id || ':' || mission_id || ':' || provider_id),
      organization_id,
      (array_agg(display_name ORDER BY version DESC))[1],
      CASE WHEN (array_agg(lifecycle_state ORDER BY version DESC))[1] = 'archived'
        THEN 'archived' ELSE 'active' END,
      max(version),
      'unknown',
      'unknown',
      jsonb_build_object('migration_source', 'stage_2_mission_provider', 'mission_id', mission_id),
      now(), now()
    FROM mission_providers
    GROUP BY organization_id, mission_id, provider_id
    ON CONFLICT (provider_account_id) DO NOTHING
    """)
  end

  defp backfill_account_versions do
    execute("""
    INSERT INTO provider_account_versions (
      provider_account_id, organization_id, version, provider_type, client_key,
      base_url, environment_ref, credential_ref, event_ingestion_mode,
      event_configuration, request_policy, guardrails, provider_configuration,
      created_at, inserted_at
    )
    SELECT
      'legacy_provider_account_' || md5(organization_id || ':' || mission_id || ':' || provider_id),
      organization_id, version, provider_type, client_key, base_url,
      environment_ref, credential_ref, 'polling', '{}'::jsonb, '{}'::jsonb,
      '{}'::jsonb, jsonb_build_object('migration_source', 'stage_2_mission_provider'),
      inserted_at, inserted_at
    FROM mission_providers
    ON CONFLICT (provider_account_id, version) DO NOTHING
    """)
  end

  defp backfill_grants do
    execute("""
    INSERT INTO provider_account_grants (
      provider_account_grant_id, organization_id, mission_id, provider_account_id,
      provider_account_version, version, lifecycle_state, restrictions,
      granted_at, grant_reason, revoked_at, revoke_reason, metadata, inserted_at
    )
    SELECT
      'legacy_provider_grant_' || md5(organization_id || ':' || mission_id || ':' || provider_id),
      organization_id, mission_id,
      'legacy_provider_account_' || md5(organization_id || ':' || mission_id || ':' || provider_id),
      version, version,
      CASE WHEN lifecycle_state = 'archived' THEN 'revoked' ELSE 'active' END,
      '{}'::jsonb, inserted_at, 'Stage 2 ownership migration',
      CASE WHEN lifecycle_state = 'archived' THEN inserted_at ELSE NULL END,
      CASE WHEN lifecycle_state = 'archived' THEN 'Mission Provider archived' ELSE NULL END,
      jsonb_build_object('migration_source', 'stage_2_mission_provider'), inserted_at
    FROM mission_providers
    ON CONFLICT (provider_account_grant_id, version) DO NOTHING
    """)
  end

  defp bind_mission_providers do
    execute("""
    UPDATE mission_providers
    SET
      provider_account_id = 'legacy_provider_account_' || md5(organization_id || ':' || mission_id || ':' || provider_id),
      provider_account_version = version,
      provider_account_grant_id = 'legacy_provider_grant_' || md5(organization_id || ':' || mission_id || ':' || provider_id),
      provider_account_grant_version = version
    WHERE provider_account_id IS NULL
    """)
  end

  defp bind_reservations do
    execute("""
    UPDATE provider_reservations AS reservations
    SET
      provider_account_id = providers.provider_account_id,
      provider_account_version = providers.provider_account_version,
      provider_account_grant_id = providers.provider_account_grant_id,
      provider_account_grant_version = providers.provider_account_grant_version
    FROM mission_providers AS providers
    WHERE reservations.organization_id = providers.organization_id
      AND reservations.mission_id = providers.mission_id
      AND reservations.provider_id = providers.provider_id
      AND reservations.provider_version = providers.version
      AND reservations.provider_account_id IS NULL
    """)
  end

  defp add_binding_constraints do
    execute("""
    ALTER TABLE mission_providers
    ADD CONSTRAINT mission_providers_complete_account_binding
    CHECK (
      (provider_account_id IS NULL AND provider_account_version IS NULL
        AND provider_account_grant_id IS NULL AND provider_account_grant_version IS NULL)
      OR
      (provider_account_id IS NOT NULL AND provider_account_version IS NOT NULL
        AND provider_account_grant_id IS NOT NULL AND provider_account_grant_version IS NOT NULL)
    )
    """)

    execute("""
    ALTER TABLE provider_reservations
    ADD CONSTRAINT provider_reservations_complete_account_binding
    CHECK (
      (provider_account_id IS NULL AND provider_account_version IS NULL
        AND provider_account_grant_id IS NULL AND provider_account_grant_version IS NULL)
      OR
      (provider_account_id IS NOT NULL AND provider_account_version IS NOT NULL
        AND provider_account_grant_id IS NOT NULL AND provider_account_grant_version IS NOT NULL)
    )
    """)

    execute("""
    ALTER TABLE mission_providers
    ADD CONSTRAINT mission_providers_account_version_fk
    FOREIGN KEY (organization_id, provider_account_id, provider_account_version)
    REFERENCES provider_account_versions (organization_id, provider_account_id, version)
    """)

    execute("""
    ALTER TABLE mission_providers
    ADD CONSTRAINT mission_providers_grant_version_fk
    FOREIGN KEY (organization_id, mission_id, provider_account_grant_id, provider_account_grant_version)
    REFERENCES provider_account_grants (organization_id, mission_id, provider_account_grant_id, version)
    """)

    execute("""
    ALTER TABLE provider_reservations
    ADD CONSTRAINT provider_reservations_account_version_fk
    FOREIGN KEY (organization_id, provider_account_id, provider_account_version)
    REFERENCES provider_account_versions (organization_id, provider_account_id, version)
    """)

    execute("""
    ALTER TABLE provider_reservations
    ADD CONSTRAINT provider_reservations_grant_version_fk
    FOREIGN KEY (organization_id, mission_id, provider_account_grant_id, provider_account_grant_version)
    REFERENCES provider_account_grants (organization_id, mission_id, provider_account_grant_id, version)
    """)
  end

  defp drop_binding_constraints do
    execute(
      "ALTER TABLE provider_reservations DROP CONSTRAINT IF EXISTS provider_reservations_complete_account_binding"
    )

    execute(
      "ALTER TABLE mission_providers DROP CONSTRAINT IF EXISTS mission_providers_complete_account_binding"
    )

    execute(
      "ALTER TABLE provider_reservations DROP CONSTRAINT IF EXISTS provider_reservations_grant_version_fk"
    )

    execute(
      "ALTER TABLE provider_reservations DROP CONSTRAINT IF EXISTS provider_reservations_account_version_fk"
    )

    execute(
      "ALTER TABLE mission_providers DROP CONSTRAINT IF EXISTS mission_providers_grant_version_fk"
    )

    execute(
      "ALTER TABLE mission_providers DROP CONSTRAINT IF EXISTS mission_providers_account_version_fk"
    )
  end

  defp validate_backfill do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM mission_providers AS providers
        LEFT JOIN provider_account_versions AS account_versions
          ON account_versions.organization_id = providers.organization_id
          AND account_versions.provider_account_id = providers.provider_account_id
          AND account_versions.version = providers.provider_account_version
        LEFT JOIN provider_account_grants AS grants
          ON grants.organization_id = providers.organization_id
          AND grants.mission_id = providers.mission_id
          AND grants.provider_account_grant_id = providers.provider_account_grant_id
          AND grants.version = providers.provider_account_grant_version
        WHERE providers.provider_account_id IS NULL
          OR providers.provider_account_version IS NULL
          OR providers.provider_account_grant_id IS NULL
          OR providers.provider_account_grant_version IS NULL
          OR account_versions.provider_account_id IS NULL
          OR grants.provider_account_grant_id IS NULL
      ) THEN
        RAISE EXCEPTION 'provider account ownership backfill is incomplete';
      END IF;

      IF EXISTS (
        SELECT 1
        FROM provider_reservations AS reservations
        LEFT JOIN provider_account_versions AS account_versions
          ON account_versions.organization_id = reservations.organization_id
          AND account_versions.provider_account_id = reservations.provider_account_id
          AND account_versions.version = reservations.provider_account_version
        LEFT JOIN provider_account_grants AS grants
          ON grants.organization_id = reservations.organization_id
          AND grants.mission_id = reservations.mission_id
          AND grants.provider_account_grant_id = reservations.provider_account_grant_id
          AND grants.version = reservations.provider_account_grant_version
        WHERE reservations.provider_account_id IS NULL
          OR reservations.provider_account_version IS NULL
          OR reservations.provider_account_grant_id IS NULL
          OR reservations.provider_account_grant_version IS NULL
          OR account_versions.provider_account_id IS NULL
          OR grants.provider_account_grant_id IS NULL
      ) THEN
        RAISE EXCEPTION 'provider reservation ownership backfill is incomplete';
      END IF;
    END
    $$
    """)
  end
end
