defmodule Cadence.Governance.PacketDefinitionContent do
  @moduledoc """
  What a governed packet definition IS, for #534's rule that it never changes under
  `(mission, packet_definition_id, version)`: the one function both version resolution
  (`Governance.resolve_packet_definition_versions/4`) and persist's check use (api-ops' condition 1).

  The content columns are derived from the two row schemas, minus an explicit exclusion list: keys,
  row ids, timestamps, and DECISIONS #73's field identity (`parameter_id`, `qualified_name`), which
  is filled in later and left out of the binding-set hash. A column added to either schema must be
  counted here as content or excluded on purpose (a test fails otherwise), so a new column can
  never read as "same content" while the stored copy silently diverges.

  Fields are compared in the form a read gets back (the field changeset's cast types), sorted by
  `field_id`.
  """

  alias Cadence.Governance.{GovernedPacketDefinitionRow, PacketDefinitionFieldRow}
  alias Cadence.Telemetry.PacketDefinition

  @excluded %{
    definition: [
      :id,
      :organization_id,
      :mission_id,
      :packet_definition_id,
      :version,
      :inserted_at
    ],
    field: [:id, :packet_definition_row_id, :parameter_id, :qualified_name, :inserted_at]
  }

  @doc "The columns excluded from content, by `:definition` or `:field`."
  @spec excluded(:definition | :field) :: [atom()]
  def excluded(kind), do: Map.fetch!(@excluded, kind)

  @doc "The content columns: every schema column not excluded."
  @spec columns(:definition | :field) :: [atom()]
  def columns(:definition),
    do: GovernedPacketDefinitionRow.__schema__(:fields) -- excluded(:definition)

  def columns(:field), do: PacketDefinitionFieldRow.__schema__(:fields) -- excluded(:field)

  @doc "A definition's content, from the in-memory struct or its stored row (fields preloaded)."
  @spec of(PacketDefinition.t() | GovernedPacketDefinitionRow.t()) :: term()
  def of(%PacketDefinition{} = definition) do
    fields =
      Enum.map(definition.fields, fn field ->
        0 |> PacketDefinitionFieldRow.changeset(field) |> Ecto.Changeset.apply_changes()
      end)

    build(Map.from_struct(definition), fields)
  end

  def of(%GovernedPacketDefinitionRow{field_rows: fields} = row) when is_list(fields),
    do: build(Map.from_struct(row), fields)

  defp build(definition, fields) do
    {Map.new(columns(:definition), &{&1, Map.get(definition, &1)}),
     fields
     |> Enum.map(&Map.new(columns(:field), fn column -> {column, Map.get(&1, column)} end))
     |> Enum.sort_by(& &1.field_id)}
  end
end
