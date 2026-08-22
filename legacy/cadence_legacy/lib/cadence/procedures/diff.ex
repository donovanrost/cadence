defmodule Cadence.Procedures.Diff do
  @moduledoc """
  Computes structural differences between procedure versions.

  Used for PR-style review views to show what changed between versions.
  Matches sections and steps by name, blocks by position within steps.

  ## Example

      diff = Diff.compute(old_version_id, new_version_id)
      # Returns:
      # %{
      #   sections: %{added: [...], removed: [...], modified: [...], moved: [...]},
      #   steps: %{added: [...], removed: [...], modified: [...], moved: [...]},
      #   blocks: %{added: [...], removed: [...], modified: [...], moved: [...]}
      # }
  """

  alias Cadence.Procedures.V2

  @type diff_result :: %{
          sections: element_diff(),
          steps: element_diff(),
          blocks: element_diff(),
          stats: diff_stats()
        }

  @type element_diff :: %{
          added: list(diff_entry()),
          removed: list(diff_entry()),
          modified: list(modified_entry()),
          moved: list(moved_entry())
        }

  @type diff_entry :: %{
          id: binary(),
          name: String.t() | nil,
          position: integer(),
          parent_id: binary() | nil
        }

  @type modified_entry :: %{
          id: binary(),
          name: String.t() | nil,
          changes: list(field_change())
        }

  @type moved_entry :: %{
          id: binary(),
          name: String.t() | nil,
          from_position: integer(),
          to_position: integer()
        }

  @type field_change :: %{
          field: atom(),
          old_value: any(),
          new_value: any()
        }

  @type diff_stats :: %{
          sections_added: integer(),
          sections_removed: integer(),
          sections_modified: integer(),
          steps_added: integer(),
          steps_removed: integer(),
          steps_modified: integer(),
          blocks_added: integer(),
          blocks_removed: integer(),
          blocks_modified: integer()
        }

  @doc """
  Computes the diff between two procedure versions.

  Returns nil if either version has no content.
  """
  @spec compute(binary(), binary()) :: diff_result() | nil
  def compute(old_version_id, new_version_id) do
    old_sections = V2.list_sections_with_steps(old_version_id)
    new_sections = V2.list_sections_with_steps(new_version_id)

    if Enum.empty?(old_sections) and Enum.empty?(new_sections) do
      nil
    else
      section_diff = diff_sections(old_sections, new_sections)
      step_diff = diff_all_steps(old_sections, new_sections)
      block_diff = diff_all_blocks(old_sections, new_sections)

      %{
        sections: section_diff,
        steps: step_diff,
        blocks: block_diff,
        stats: compute_stats(section_diff, step_diff, block_diff)
      }
    end
  end

  @doc """
  Returns the diff status for a specific element.

  Returns :added, :removed, :modified, :moved, or :unchanged
  """
  @spec element_status(diff_result(), :section | :step | :block, binary()) :: atom()
  def element_status(diff, element_type, element_id) do
    elements =
      case element_type do
        :section -> diff.sections
        :step -> diff.steps
        :block -> diff.blocks
      end

    cond do
      Enum.any?(elements.added, &(&1.id == element_id)) -> :added
      Enum.any?(elements.removed, &(&1.id == element_id)) -> :removed
      Enum.any?(elements.modified, &(&1.id == element_id)) -> :modified
      Enum.any?(elements.moved, &(&1.id == element_id)) -> :moved
      true -> :unchanged
    end
  end

  @doc """
  Creates a lookup map from element IDs to their diff status.

  Useful for efficiently rendering diff badges in UI.
  """
  @spec build_status_map(diff_result()) :: %{binary() => atom()}
  def build_status_map(diff) do
    %{}
    |> add_statuses(diff.sections.added, :added)
    |> add_statuses(diff.sections.removed, :removed)
    |> add_statuses(diff.sections.modified, :modified)
    |> add_statuses(diff.sections.moved, :moved)
    |> add_statuses(diff.steps.added, :added)
    |> add_statuses(diff.steps.removed, :removed)
    |> add_statuses(diff.steps.modified, :modified)
    |> add_statuses(diff.steps.moved, :moved)
    |> add_statuses(diff.blocks.added, :added)
    |> add_statuses(diff.blocks.removed, :removed)
    |> add_statuses(diff.blocks.modified, :modified)
    |> add_statuses(diff.blocks.moved, :moved)
  end

  # ── Section Diffing ────────────────────────────────────────────────────

  defp diff_sections(old_sections, new_sections) do
    old_by_name = Map.new(old_sections, &{&1.name, &1})
    new_by_name = Map.new(new_sections, &{&1.name, &1})

    old_names = MapSet.new(Map.keys(old_by_name))
    new_names = MapSet.new(Map.keys(new_by_name))

    added_names = MapSet.difference(new_names, old_names)
    removed_names = MapSet.difference(old_names, new_names)
    common_names = MapSet.intersection(old_names, new_names)

    added =
      Enum.map(added_names, fn name ->
        section = new_by_name[name]
        %{id: section.id, name: section.name, position: section.position, parent_id: nil}
      end)

    removed =
      Enum.map(removed_names, fn name ->
        section = old_by_name[name]
        %{id: section.id, name: section.name, position: section.position, parent_id: nil}
      end)

    {modified, moved} =
      Enum.reduce(common_names, {[], []}, fn name, {mod_acc, mov_acc} ->
        old = old_by_name[name]
        new = new_by_name[name]

        changes = compare_section_fields(old, new)
        position_changed = old.position != new.position

        mod_acc =
          if Enum.any?(changes) do
            [%{id: new.id, name: new.name, changes: changes} | mod_acc]
          else
            mod_acc
          end

        mov_acc =
          if position_changed do
            [
              %{
                id: new.id,
                name: new.name,
                from_position: old.position,
                to_position: new.position
              }
              | mov_acc
            ]
          else
            mov_acc
          end

        {mod_acc, mov_acc}
      end)

    %{added: added, removed: removed, modified: modified, moved: moved}
  end

  defp compare_section_fields(old, new) do
    fields = [:description, :collapsed_by_default]

    Enum.reduce(fields, [], fn field, acc ->
      old_val = Map.get(old, field)
      new_val = Map.get(new, field)

      if old_val != new_val do
        [%{field: field, old_value: old_val, new_value: new_val} | acc]
      else
        acc
      end
    end)
  end

  # ── Step Diffing ───────────────────────────────────────────────────────

  defp diff_all_steps(old_sections, new_sections) do
    # Build maps of steps keyed by "section_name:step_name" for matching
    old_steps = extract_steps(old_sections)
    new_steps = extract_steps(new_sections)

    old_by_key = Map.new(old_steps, fn {key, step, _section} -> {key, step} end)
    new_by_key = Map.new(new_steps, fn {key, step, _section} -> {key, step} end)

    old_keys = MapSet.new(Map.keys(old_by_key))
    new_keys = MapSet.new(Map.keys(new_by_key))

    added_keys = MapSet.difference(new_keys, old_keys)
    removed_keys = MapSet.difference(old_keys, new_keys)
    common_keys = MapSet.intersection(old_keys, new_keys)

    added =
      Enum.map(added_keys, fn key ->
        step = new_by_key[key]
        %{id: step.id, name: step.name, position: step.position, parent_id: step.section_id}
      end)

    removed =
      Enum.map(removed_keys, fn key ->
        step = old_by_key[key]
        %{id: step.id, name: step.name, position: step.position, parent_id: step.section_id}
      end)

    {modified, moved} =
      Enum.reduce(common_keys, {[], []}, fn key, {mod_acc, mov_acc} ->
        old = old_by_key[key]
        new = new_by_key[key]

        changes = compare_step_fields(old, new)
        position_changed = old.position != new.position

        mod_acc =
          if Enum.any?(changes) do
            [%{id: new.id, name: new.name, changes: changes} | mod_acc]
          else
            mod_acc
          end

        mov_acc =
          if position_changed do
            [
              %{
                id: new.id,
                name: new.name,
                from_position: old.position,
                to_position: new.position
              }
              | mov_acc
            ]
          else
            mov_acc
          end

        {mod_acc, mov_acc}
      end)

    %{added: added, removed: removed, modified: modified, moved: moved}
  end

  defp extract_steps(sections) do
    Enum.flat_map(sections, fn section ->
      Enum.map(section.steps, fn step ->
        key = "#{section.name}:#{step.name}"
        {key, step, section}
      end)
    end)
  end

  defp compare_step_fields(old, new) do
    fields = [
      :title,
      :requires_signoff,
      :required_roles,
      :signoff_logic,
      :depends_on,
      :dependency_logic,
      :condition,
      :on_fail,
      :estimated_duration_seconds
    ]

    Enum.reduce(fields, [], fn field, acc ->
      old_val = Map.get(old, field)
      new_val = Map.get(new, field)

      if old_val != new_val do
        [%{field: field, old_value: old_val, new_value: new_val} | acc]
      else
        acc
      end
    end)
  end

  # ── Block Diffing ──────────────────────────────────────────────────────

  defp diff_all_blocks(old_sections, new_sections) do
    # Build maps of blocks keyed by "section_name:step_name:position" for matching
    old_blocks = extract_blocks(old_sections)
    new_blocks = extract_blocks(new_sections)

    old_by_key = Map.new(old_blocks, fn {key, block, _step} -> {key, block} end)
    new_by_key = Map.new(new_blocks, fn {key, block, _step} -> {key, block} end)

    old_keys = MapSet.new(Map.keys(old_by_key))
    new_keys = MapSet.new(Map.keys(new_by_key))

    added_keys = MapSet.difference(new_keys, old_keys)
    removed_keys = MapSet.difference(old_keys, new_keys)
    common_keys = MapSet.intersection(old_keys, new_keys)

    added =
      Enum.map(added_keys, fn key ->
        block = new_by_key[key]
        %{id: block.id, name: block.name, position: block.position, parent_id: block.step_id}
      end)

    removed =
      Enum.map(removed_keys, fn key ->
        block = old_by_key[key]
        %{id: block.id, name: block.name, position: block.position, parent_id: block.step_id}
      end)

    modified =
      Enum.reduce(common_keys, [], fn key, acc ->
        old = old_by_key[key]
        new = new_by_key[key]

        changes = compare_block_fields(old, new)

        if Enum.any?(changes) do
          [%{id: new.id, name: new.name, changes: changes} | acc]
        else
          acc
        end
      end)

    # Blocks don't have a separate "moved" concept since position is part of the key
    %{added: added, removed: removed, modified: modified, moved: []}
  end

  defp extract_blocks(sections) do
    Enum.flat_map(sections, &extract_section_blocks/1)
  end

  defp extract_section_blocks(section) do
    Enum.flat_map(section.steps, fn step ->
      extract_step_blocks(section.name, step)
    end)
  end

  defp extract_step_blocks(section_name, step) do
    Enum.map(step.blocks, fn block ->
      key = "#{section_name}:#{step.name}:#{block.position}"
      {key, block, step}
    end)
  end

  defp compare_block_fields(old, new) do
    fields = [:block_type, :name, :label, :required, :content]

    Enum.reduce(fields, [], fn field, acc ->
      old_val = Map.get(old, field)
      new_val = Map.get(new, field)

      if old_val != new_val do
        [%{field: field, old_value: old_val, new_value: new_val} | acc]
      else
        acc
      end
    end)
  end

  # ── Stats ──────────────────────────────────────────────────────────────

  defp compute_stats(section_diff, step_diff, block_diff) do
    %{
      sections_added: length(section_diff.added),
      sections_removed: length(section_diff.removed),
      sections_modified: length(section_diff.modified),
      steps_added: length(step_diff.added),
      steps_removed: length(step_diff.removed),
      steps_modified: length(step_diff.modified),
      blocks_added: length(block_diff.added),
      blocks_removed: length(block_diff.removed),
      blocks_modified: length(block_diff.modified)
    }
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  defp add_statuses(map, entries, status) do
    Enum.reduce(entries, map, fn entry, acc ->
      Map.put(acc, entry.id, status)
    end)
  end
end
