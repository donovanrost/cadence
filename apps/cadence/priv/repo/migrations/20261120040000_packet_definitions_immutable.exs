defmodule Cadence.Repo.Migrations.PacketDefinitionsImmutable do
  use Ecto.Migration

  # #534 (ca-security's point 2, as #116): a governed packet definition never changes under
  # (mission, packet_definition_id, version). Triggers only, no data change:
  # - governed_packet_definitions refuses UPDATE and DELETE;
  # - governed_packet_definition_fields refuses DELETE, and any UPDATE except DECISIONS #73's
  #   identity fill: parameter_id and qualified_name may go from NULL to a value, or be rewritten
  #   with their own value; every other column must be unchanged.
  def up do
    execute("""
    CREATE FUNCTION governed_packet_definition_immutable() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION '% is immutable under its key (#534)', TG_TABLE_NAME;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE TRIGGER governed_packet_definitions_immutable
      BEFORE UPDATE OR DELETE ON governed_packet_definitions
      FOR EACH ROW EXECUTE FUNCTION governed_packet_definition_immutable()
    """)

    execute("""
    CREATE TRIGGER governed_packet_definition_fields_no_delete
      BEFORE DELETE ON governed_packet_definition_fields
      FOR EACH ROW EXECUTE FUNCTION governed_packet_definition_immutable()
    """)

    execute("""
    CREATE FUNCTION governed_packet_definition_field_fill_only() RETURNS trigger AS $$
    BEGIN
      IF NEW.id IS DISTINCT FROM OLD.id
         OR NEW.packet_definition_row_id IS DISTINCT FROM OLD.packet_definition_row_id
         OR NEW.field_id IS DISTINCT FROM OLD.field_id
         OR NEW.name IS DISTINCT FROM OLD.name
         OR NEW.offset_bits IS DISTINCT FROM OLD.offset_bits
         OR NEW.size_bits IS DISTINCT FROM OLD.size_bits
         OR NEW.data_type IS DISTINCT FROM OLD.data_type
         OR NEW.byte_order IS DISTINCT FROM OLD.byte_order
         OR NEW.engineering_unit IS DISTINCT FROM OLD.engineering_unit
         OR NEW.inserted_at IS DISTINCT FROM OLD.inserted_at
         OR (OLD.parameter_id IS NOT NULL AND NEW.parameter_id IS DISTINCT FROM OLD.parameter_id)
         OR (OLD.qualified_name IS NOT NULL AND NEW.qualified_name IS DISTINCT FROM OLD.qualified_name)
      THEN
        RAISE EXCEPTION 'governed_packet_definition_fields is immutable under its key except the #73 identity fill (#534)';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    execute("""
    CREATE TRIGGER governed_packet_definition_fields_fill_only
      BEFORE UPDATE ON governed_packet_definition_fields
      FOR EACH ROW EXECUTE FUNCTION governed_packet_definition_field_fill_only()
    """)
  end

  def down do
    execute(
      "DROP TRIGGER governed_packet_definition_fields_fill_only ON governed_packet_definition_fields"
    )

    execute("DROP FUNCTION governed_packet_definition_field_fill_only()")

    execute(
      "DROP TRIGGER governed_packet_definition_fields_no_delete ON governed_packet_definition_fields"
    )

    execute("DROP TRIGGER governed_packet_definitions_immutable ON governed_packet_definitions")
    execute("DROP FUNCTION governed_packet_definition_immutable()")
  end
end
