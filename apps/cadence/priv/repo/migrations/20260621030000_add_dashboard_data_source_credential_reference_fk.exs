defmodule Cadence.Repo.Migrations.AddDashboardDataSourceCredentialReferenceFk do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE dashboard_data_sources
    ADD CONSTRAINT dashboard_data_sources_credentials_ref_fk
    FOREIGN KEY (credentials_ref)
    REFERENCES dashboard_source_credential_references (credentials_ref)
    """)
  end

  def down do
    execute("""
    ALTER TABLE dashboard_data_sources
    DROP CONSTRAINT IF EXISTS dashboard_data_sources_credentials_ref_fk
    """)
  end
end
