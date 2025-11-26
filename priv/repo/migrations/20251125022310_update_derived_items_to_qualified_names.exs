defmodule Cadence.Repo.Migrations.UpdateDerivedItemsToQualifiedNames do
  use Ecto.Migration
  import Ecto.Query
  alias Cadence.Repo

  def up do
    # Get all existing derived items
    derived_items = Repo.all(
      from d in "derived_items",
      select: %{
        id: d.id,
        mission_id: d.mission_id,
        expression: d.expression,
        source_items: d.source_items
      }
    )

    IO.puts("\nUpdating #{length(derived_items)} derived items to use qualified names...")

    Enum.each(derived_items, fn item ->
      case update_derived_item_expressions(item) do
        {:ok, new_expression, new_source_items} ->
          Repo.update_all(
            from(d in "derived_items", where: d.id == ^item.id),
            set: [
              expression: new_expression,
              source_items: new_source_items
            ]
          )

          IO.puts("  ✓ Updated derived item")

        {:error, reason} ->
          IO.puts("  ✗ Failed to update derived item: #{inspect(reason)}")
          IO.puts("    You may need to manually update this item's expression")
      end
    end)

    IO.puts("\nMigration complete! Please verify your derived item expressions.")
  end

  def down do
    IO.puts("\nWARNING: Cannot automatically revert qualified names to unqualified names.")
    IO.puts("Manual intervention required if you need to rollback.")
  end

  defp update_derived_item_expressions(item) do
    # Get the mission's active definition set
    definition_set = Repo.one(
      from ds in "definition_sets",
      where: ds.mission_id == ^item.mission_id,
      where: not is_nil(ds.published_at),
      where: is_nil(ds.superseded_at),
      select: %{id: ds.id},
      limit: 1
    )

    if definition_set do
      # Build a map of item_name => packet_name
      item_to_packet_map = build_item_to_packet_map(definition_set.id)

      # Update expression and source_items
      case qualify_expression(item.expression, item_to_packet_map) do
        {:ok, new_expression} ->
          new_source_items = Enum.map(item.source_items || [], fn short_name ->
            Map.get(item_to_packet_map, short_name, "UNKNOWN.#{short_name}")
          end)

          {:ok, new_expression, new_source_items}

        error ->
          error
      end
    else
      # No active definition set - skip this item
      IO.puts("    No active DefinitionSet found for mission #{item.mission_id}, skipping...")
      {:error, :no_definition_set}
    end
  end

  defp build_item_to_packet_map(definition_set_id) do
    # Query all packet items for this definition set
    packet_items = Repo.all(
      from pi in "packet_items",
      join: pd in "packet_definitions",
      on: pi.packet_definition_id == pd.id,
      where: pd.definition_set_id == ^definition_set_id,
      select: %{
        item_name: pi.name,
        packet_name: pd.name
      }
    )

    # Build map of item_name => "PACKET.ITEM"
    Enum.reduce(packet_items, %{}, fn %{item_name: item, packet_name: packet}, acc ->
      Map.put(acc, item, "#{packet}.#{item}")
    end)
  end

  defp qualify_expression(expression, item_to_packet_map) do
    # Simple regex-based replacement for variable names
    # Uses negative lookahead/lookbehind to avoid matching words adjacent to dots (already qualified)
    result = Regex.replace(~r/(?<!\.)(?<!\w)\b([a-zA-Z_][a-zA-Z0-9_]*)\b(?!\w)(?!\.)/, expression, fn _, var_name ->
      # Don't replace if it's already qualified (contains a dot) or is a number
      cond do
        String.contains?(var_name, ".") ->
          var_name

        Map.has_key?(item_to_packet_map, var_name) ->
          Map.get(item_to_packet_map, var_name)

        true ->
          # Unknown variable - keep as is and warn
          IO.puts("      Warning: Unknown variable '#{var_name}' in expression")
          var_name
      end
    end)

    {:ok, result}
  end
end
