defmodule Cadence.Repo.Migrations.AddDataSourceCredentialReferenceFk do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE data_source_definitions
    ADD CONSTRAINT data_source_definitions_credentials_ref_fk
    FOREIGN KEY (credentials_ref)
    REFERENCES data_source_credential_references (credentials_ref)
    """)
  end

  def down do
    execute("""
    ALTER TABLE data_source_definitions
    DROP CONSTRAINT IF EXISTS data_source_definitions_credentials_ref_fk
    """)
  end
end
