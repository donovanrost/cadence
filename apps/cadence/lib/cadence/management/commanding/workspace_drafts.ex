defmodule Cadence.Management.Commanding.WorkspaceDrafts do
  @moduledoc "Bounded multi-endpoint preparation using the existing reviewed stage draft lifecycle."
  alias Cadence.Catalog.Command.Compatibility, as: CommandCompatibility

  import Ecto.Query
  alias Cadence.Commanding.RequestValidation
  alias Cadence.Management.Commanding.{StageAccess, StageCatalog, StageItemAuthoring}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  def preview(scope, mission, stage_id, input) do
    with {:ok, commands, notes} <- inputs(input),
         {:ok, held} <-
           StageAccess.with_stage(scope, mission, stage_id, :write, fn fresh, _, stage ->
             prepare_batch(fresh, mission, stage, input, commands, notes)
           end),
         {:ok, _} <- public_preview(held) do
      {:ok, held}
    end
  end

  defp prepare_batch(scope, mission, stage, input, commands, notes) do
    next_order = next_order(stage)

    with true <- next_order + length(commands) <= 2_147_483_647,
         {:ok, items} <- preview_items(scope, mission, stage.command_stage_id, input, commands),
         {:ok, :compatible} <- compatible_items(items) do
      held = %{
        stage_id: stage.command_stage_id,
        actor_id: scope.user.user_id,
        items: items,
        notes: notes,
        first_order: next_order
      }

      {:ok, Map.put(held, :token, RequestValidation.authoring_digest(held))}
    else
      false -> {:error, :invalid_command_stage_input}
      error -> error
    end
  end

  def save(scope, mission, stage_id, write_token, held, input) do
    with :ok <- expected(held, stage_id, write_token, input) do
      StageAccess.with_stage(
        scope,
        mission,
        stage_id,
        :write,
        fn fresh, _, stage ->
          save_batch(fresh, mission, stage, held, write_token)
        end,
        notify: true
      )
    end
  end

  defp save_batch(scope, mission, stage, held, write_token) do
    with true <- scope.user.user_id == held.actor_id,
         :ok <- current_position(stage, held),
         {:ok, receipts} <- save_items(scope, mission, held, write_token) do
      {:ok, receipt(held, receipts)}
    else
      false -> {:error, :unavailable}
      error -> error
    end
  end

  defp current_position(stage, held) do
    if next_order(stage) == held.first_order,
      do: :ok,
      else: {:error, :command_stage_changed}
  end

  def current?(scope, mission, held) do
    result =
      StageAccess.with_stage(scope, mission, held.stage_id, :read, fn fresh, _, stage ->
        current_preview(fresh, stage, held)
      end)

    result == {:ok, :current}
  end

  defp current_preview(scope, stage, held) do
    requests = Enum.map(held.items, & &1.authoring.request)

    targets =
      Map.new(
        held.items,
        &{&1.authoring.request.command_request_id, &1.authoring.expected_target}
      )

    basis = hd(held.items).authoring.expected_basis

    with true <- scope.user.user_id == held.actor_id,
         :ok <- current_position(stage, held) do
      RequestValidation.with_authoring_requests(requests, basis, targets, fn _, _ ->
        {:ok, :current}
      end)
    else
      _ -> {:error, :command_stage_changed}
    end
  end

  def recover(scope, mission, held) do
    StageAccess.with_stage(scope, mission, held.stage_id, :read, fn fresh, _, stage ->
      ids = Enum.map(held.items, & &1.item_id)

      rows =
        stage
        |> StageCatalog.item_query()
        |> where([row], row.staged_command_item_id in ^ids)
        |> Repo.all()

      by_id = Map.new(rows, &{&1.staged_command_item_id, &1})

      valid? =
        fresh.user.user_id == held.actor_id and length(rows) == length(ids) and
          Enum.all?(Enum.with_index(held.items), fn {item, index} ->
            same_draft?(by_id[item.item_id], item.authoring.request, held, index)
          end)

      if valid? do
        {:ok, recovered_receipt(held, ids, by_id)}
      else
        {:error, :unconfirmed}
      end
    end)
  end

  defp recovered_receipt(held, ids, by_id) do
    receipts =
      Enum.map(ids, fn id ->
        %{"item_id" => id, "updated_at" => DateTime.to_iso8601(by_id[id].updated_at)}
      end)

    receipt(held, receipts)
  end

  def public_preview(held) do
    public = %{
      "token" => held.token,
      "stage_id" => held.stage_id,
      "actor_id" => held.actor_id,
      "notes" => held.notes,
      "items" =>
        Enum.with_index(held.items, fn item, index ->
          Map.put(StageItemAuthoring.public_preview(item), "order", held.first_order + index)
        end)
    }

    case Jason.encode(public) do
      {:ok, json} when byte_size(json) <= 524_288 -> {:ok, public}
      _ -> {:error, :command_stage_preview_too_large}
    end
  end

  defp inputs(%{"expected_stage" => stage, "commands" => commands, "notes" => notes} = input)
       when map_size(input) == 3 and is_binary(stage) and is_list(commands) and
              length(commands) in 1..25 do
    targets = Enum.map(commands, &if(is_map(&1), do: &1["source_endpoint_ref"]))

    definitions =
      Enum.map(commands, &if(is_map(&1), do: {&1["command_id"], &1["expected_basis"]}))

    if length(Enum.uniq(targets)) == length(commands) and length(Enum.uniq(definitions)) == 1 and
         valid_notes?(notes) do
      {:ok, commands, notes}
    else
      {:error, :invalid_command_stage_input}
    end
  end

  defp inputs(_), do: {:error, :invalid_command_stage_input}
  defp valid_notes?(nil), do: true

  defp valid_notes?(notes) when is_binary(notes),
    do: String.valid?(notes) and byte_size(notes) <= 4_000

  defp valid_notes?(_), do: false

  defp preview_items(scope, mission, stage_id, input, commands) do
    Enum.reduce_while(commands, {:ok, []}, fn command, {:ok, items} ->
      case StageItemAuthoring.preview(scope, mission, stage_id, nil, %{
             "expected_stage" => input["expected_stage"],
             "expected_item" => nil,
             "command" => command
           }) do
        {:ok, item} -> {:cont, {:ok, items ++ [item]}}
        error -> {:halt, error}
      end
    end)
  end

  defp compatible_items([first | _] = items) do
    requests = Enum.map(items, & &1.authoring.request)

    targets =
      Map.new(items, &{&1.authoring.request.command_request_id, &1.authoring.expected_target})

    RequestValidation.with_authoring_requests(
      requests,
      first.authoring.expected_basis,
      targets,
      fn validated, _ ->
        fingerprints =
          Enum.map(validated, fn {request, state} ->
            CommandCompatibility.fingerprint(
              state.snapshot.catalog,
              request.command_id
            )
          end)

        if Enum.all?(fingerprints, &match?({:ok, _}, &1)) and length(Enum.uniq(fingerprints)) == 1,
          do: {:ok, :compatible},
          else: {:error, :incompatible_spacecraft_commands}
      end
    )
  end

  defp save_items(scope, mission, held, token) do
    held.items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, receipts} ->
      input = %{
        "expected_write" => token,
        "expected_preview" => item.token,
        "expected_stage" => item.expected_stage,
        "notes" => held.notes,
        "order" => held.first_order + index
      }

      case StageItemAuthoring.save(scope, mission, held.stage_id, token, item, input) do
        {:ok, result} -> {:cont, {:ok, receipts ++ [result]}}
        error -> {:halt, error}
      end
    end)
  end

  defp next_order(stage) do
    query = stage |> StageCatalog.item_query() |> exclude(:select)
    (Repo.one(from(row in query, select: max(row.item_order))) || -1) + 1
  end

  defp expected(
         held,
         stage_id,
         write,
         %{"expected_preview" => preview, "expected_write" => token} = input
       )
       when map_size(input) == 2 and is_map(held) do
    if token == write and preview == held.token and stage_id == held.stage_id and
         held.token == RequestValidation.authoring_digest(Map.delete(held, :token)),
       do: :ok,
       else: {:error, :command_stage_changed}
  end

  defp expected(_, _, _, _), do: {:error, :command_stage_changed}

  defp same_draft?(nil, _, _, _), do: false

  defp same_draft?(row, request, held, index) do
    same_command?(row, request) and row.notes_available and
      is_map(row.argument_values_document) and
      JsonDocument.unwrap_value(row.argument_values_document) == request.argument_values and
      row.priority == request.priority and row.not_before == request.not_before and
      row.expires_at == request.expires_at and row.notes == held.notes and
      row.item_order == held.first_order + index
  end

  defp same_command?(row, request) do
    row.source_endpoint_ref == request.source_endpoint_ref and
      row.mission_model_revision_id == request.mission_model_revision_id and
      row.command_id == request.command_id
  end

  defp receipt(held, items),
    do: %{
      "operation" => "items_created",
      "stage_id" => held.stage_id,
      "actor_id" => held.actor_id,
      "items" => Enum.map(items, &Map.take(&1, ["item_id", "updated_at"]))
    }
end
