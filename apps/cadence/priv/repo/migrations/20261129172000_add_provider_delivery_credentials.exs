defmodule Cadence.Repo.Migrations.AddProviderDeliveryCredentials do
  use Ecto.Migration

  def change do
    create table(:provider_delivery_credentials, primary_key: false) do
      add(:credential_ref, :text, primary_key: true)
      add(:organization_id, :text, null: false)
      add(:mission_id, :text, null: false)
      add(:provider_id, :text, null: false)
      add(:provider_account_id, :text, null: false)
      add(:provider_account_grant_id, :text, null: false)
      add(:provider_binding_id, :text, null: false)
      add(:retired_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(
        :provider_delivery_credentials,
        [:organization_id, :mission_id, :provider_binding_id],
        name: :provider_delivery_credential_binding_idx
      )
    )

    create table(:provider_delivery_certificate_generations, primary_key: false) do
      add(:fingerprint, :text, primary_key: true)
      add(:public_key_fingerprint, :text, null: false)

      add(
        :credential_ref,
        references(:provider_delivery_credentials, column: :credential_ref, type: :text),
        null: false
      )

      add(:generation, :integer, null: false)
      add(:state, :text, null: false)
      add(:expires_at, :utc_datetime, null: false)
      add(:overlap_ends_at, :utc_datetime_usec)
      add(:revoked_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:provider_delivery_certificate_generations, [:public_key_fingerprint],
        name: :provider_delivery_certificate_public_key_idx
      )
    )

    create(
      unique_index(:provider_delivery_certificate_generations, [:credential_ref, :generation],
        name: :provider_delivery_certificate_generation_idx
      )
    )

    create(
      unique_index(:provider_delivery_certificate_generations, [:credential_ref, :state],
        where: "state IN ('current', 'previous')",
        name: :provider_delivery_certificate_active_generation_idx
      )
    )

    create(
      constraint(
        :provider_delivery_certificate_generations,
        :provider_delivery_certificate_lifecycle,
        check:
          "generation > 0 AND ((state = 'current' AND overlap_ends_at IS NULL AND revoked_at IS NULL) OR (state = 'previous' AND overlap_ends_at IS NOT NULL AND revoked_at IS NULL) OR (state = 'revoked' AND revoked_at IS NOT NULL))"
      )
    )

    execute(
      """
      CREATE FUNCTION cadence_provider_delivery_terminal() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'provider delivery credential records cannot be removed or changed after revocation or retirement'
          USING ERRCODE = 'check_violation';
      END;
      $$
      """,
      "DROP FUNCTION cadence_provider_delivery_terminal()"
    )

    protect_terminal_records("provider_delivery_credentials", "OLD.retired_at IS NOT NULL")
    protect_terminal_records("provider_delivery_certificate_generations", "OLD.state = 'revoked'")
  end

  defp protect_terminal_records(table, terminal) do
    execute(
      """
      CREATE TRIGGER delivery_terminal_update BEFORE UPDATE ON #{table}
      FOR EACH ROW WHEN (#{terminal}) EXECUTE FUNCTION cadence_provider_delivery_terminal()
      """,
      "DROP TRIGGER delivery_terminal_update ON #{table}"
    )

    execute(
      """
      CREATE TRIGGER delivery_prevent_delete BEFORE DELETE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION cadence_provider_delivery_terminal()
      """,
      "DROP TRIGGER delivery_prevent_delete ON #{table}"
    )

    execute(
      """
      CREATE TRIGGER delivery_prevent_truncate BEFORE TRUNCATE ON #{table}
      FOR EACH STATEMENT EXECUTE FUNCTION cadence_provider_delivery_terminal()
      """,
      "DROP TRIGGER delivery_prevent_truncate ON #{table}"
    )
  end
end
