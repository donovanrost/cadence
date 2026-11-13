defmodule Cadence.Repo.Migrations.ProviderAuditEntriesActionIndex do
  use Ecto.Migration

  # qa #51: the organization audit reads provider audit entries by exact action, newest first,
  # and resolution failures are deduplicated by action. Without this the read walked every
  # entry of the organization (4.1M routine resolves on :4011). If-not-exists: the same index may
  # be built by hand ahead of a restart, with the same name.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create_if_not_exists(
      index(:provider_audit_entries, [:organization_id, :action, :recorded_at],
        name: :provider_audit_entries_org_action_time_idx,
        concurrently: true
      )
    )
  end
end
