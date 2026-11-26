defmodule Cadence.Repo.Migrations.PacketDefinitionsNoTruncate do
  use Ecto.Migration

  # #534 follow-up (ca-security on #548, as #116 and #504): row triggers don't fire on TRUNCATE,
  # so both packet definition tables also refuse it with a statement trigger.
  def up do
    execute("""
    CREATE FUNCTION governed_packet_definition_no_truncate() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION '% is immutable under its key (#534): TRUNCATE refused', TG_TABLE_NAME;
    END;
    $$ LANGUAGE plpgsql
    """)

    for table <- ["governed_packet_definitions", "governed_packet_definition_fields"] do
      execute("""
      CREATE TRIGGER #{table}_no_truncate BEFORE TRUNCATE ON #{table}
        FOR EACH STATEMENT EXECUTE FUNCTION governed_packet_definition_no_truncate()
      """)
    end
  end

  def down do
    for table <- ["governed_packet_definitions", "governed_packet_definition_fields"] do
      execute("DROP TRIGGER #{table}_no_truncate ON #{table}")
    end

    execute("DROP FUNCTION governed_packet_definition_no_truncate()")
  end
end
