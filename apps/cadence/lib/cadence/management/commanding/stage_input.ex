defmodule Cadence.Management.Commanding.StageInput do
  @moduledoc "Finite stage inputs; actor, scope, durable identities and resolved requests are server-owned."
  alias Cadence.Ids

  @states ~w(draft in_review ready_to_submit submitted canceled)
  @editable_states ~w(draft in_review ready_to_submit canceled)
  @max_order 2_147_483_647

  def directory(input) when is_map(input) and map_size(input) <= 3 do
    parse(Map.merge(%{"after" => "", "state" => "", "query" => ""}, input), [
      {"after", :after, &optional_id?/1},
      {"state", :state, &(&1 in ["" | @states])},
      {"query", :query, &text?(&1, 240)}
    ])
  end

  def directory(_), do: invalid()

  def workbench(input) when is_map(input) and map_size(input) <= 4 do
    with {:ok, query} <-
           parse(
             Map.merge(%{"after" => "", "after_order" => "", "item" => "", "state" => ""}, input),
             [
               {"after", :after, &optional_id?/1},
               {"after_order", :after_order, &cursor_order?/1},
               {"item", :item, &optional_id?/1},
               {"state", :state, &(&1 in ~w(draft submitted canceled) or &1 == "")}
             ]
           ),
         true <- query.after == "" == (query.after_order == "") do
      {:ok,
       %{
         query
         | after_order:
             if(query.after_order == "", do: nil, else: String.to_integer(query.after_order))
       }}
    else
      _ -> invalid()
    end
  end

  def workbench(_), do: invalid()

  def create(input) do
    parse(input, [
      {"expected_write", :expected_write, &digest?/1},
      {"name", :name, &name?/1},
      {"description", :description, &optional_text?(&1, 4_000)},
      {"visibility", :visibility, &(&1 in ~w(private shared))}
    ])
  end

  def edit_stage(input) do
    parse(input, [
      {"expected_write", :expected_write, &digest?/1},
      {"expected_stage", :expected_stage, &digest?/1},
      {"name", :name, &name?/1},
      {"description", :description, &optional_text?(&1, 4_000)},
      {"visibility", :visibility, &(&1 in ~w(private shared))},
      {"state", :state, &(&1 in @editable_states)}
    ])
  end

  def add_item(input), do: parse(input, item_fields())

  def edit_item(input) do
    parse(input, [{"expected_item", :expected_item, &digest?/1} | item_fields()])
  end

  def cancel_item(input) do
    parse(input, [
      {"expected_write", :expected_write, &digest?/1},
      {"expected_stage", :expected_stage, &digest?/1},
      {"expected_item", :expected_item, &digest?/1}
    ])
  end

  def edit_details(input) do
    parse(input, [
      {"expected_write", :expected_write, &digest?/1},
      {"expected_stage", :expected_stage, &digest?/1},
      {"expected_item", :expected_item, &digest?/1},
      {"notes", :notes, &optional_text?(&1, 4_000)},
      {"order", :order, &(is_integer(&1) and &1 in 0..@max_order)}
    ])
  end

  def preview_submission(input) do
    parse(input, [
      {"expected_stage", :expected_stage, &digest?/1},
      {"items", :items, &items?/1}
    ])
  end

  def submit(input) do
    parse(input, [
      {"expected_write", :expected_write, &digest?/1},
      {"expected_preview", :expected_preview, &digest?/1}
    ])
  end

  defp item_fields do
    [
      {"expected_write", :expected_write, &digest?/1},
      {"expected_stage", :expected_stage, &digest?/1},
      {"expected_preview", :expected_preview, &digest?/1},
      {"notes", :notes, &optional_text?(&1, 4_000)},
      {"order", :order, &(is_integer(&1) and &1 in 0..@max_order)}
    ]
  end

  defp parse(input, fields) when is_map(input) do
    if map_size(input) == length(fields) and
         Enum.all?(fields, &valid_field?(input, &1)) do
      {:ok, Map.new(fields, fn {key, target, _} -> {target, Map.fetch!(input, key)} end)}
    else
      invalid()
    end
  end

  defp parse(_, _), do: invalid()

  defp valid_field?(input, {key, _, validate}) do
    case Map.fetch(input, key) do
      {:ok, value} -> validate.(value)
      :error -> false
    end
  end

  defp items?(items) when is_list(items) and length(items) in 1..25 do
    Enum.all?(items, &selected_item?/1) and
      length(Enum.uniq_by(items, & &1["id"])) == length(items)
  end

  defp items?(_), do: false

  defp selected_item?(%{"id" => id, "expected_item" => expected} = item)
       when map_size(item) == 2,
       do: Ids.valid_identifier?(id) and digest?(expected)

  defp selected_item?(_), do: false
  defp optional_id?(""), do: true
  defp optional_id?(value), do: Ids.valid_identifier?(value)
  defp cursor_order?(""), do: true

  defp cursor_order?(value) when is_binary(value) and byte_size(value) <= 10 do
    case Integer.parse(value) do
      {order, ""} when order in 0..@max_order -> Integer.to_string(order) == value
      _ -> false
    end
  end

  defp cursor_order?(_), do: false
  defp optional_text?(nil, _), do: true
  defp optional_text?(value, max), do: text?(value, max)
  defp name?(value), do: text?(value, 240) and String.trim(value) != ""
  defp digest?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)

  defp text?(value, max) do
    is_binary(value) and byte_size(value) <= max and String.valid?(value) and
      not Regex.match?(~r/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/, value)
  end

  defp invalid, do: {:error, :invalid_command_stage_input}
end
