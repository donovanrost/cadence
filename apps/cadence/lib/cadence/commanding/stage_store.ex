defmodule Cadence.Commanding.StageStore do
  @moduledoc """
  Persists command stages and staged items, including batch submission into requests.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Ecto.Multi

  alias Cadence.Commanding.{
    CommandRequest,
    CommandRequestRow,
    CommandStage,
    CommandStageRow,
    LifecyclePolicy,
    RequestValidation,
    StagedCommandItem,
    StagedCommandItemRow
  }

  alias Cadence.Missions
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo
  alias Cadence.SourceEndpoints

  @spec persist_stage(binary(), CommandStage.t()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  def persist_stage(organization_id, %CommandStage{} = command_stage)
      when is_binary(organization_id) do
    with {:ok, scoped_command_stage} <- put_organization_scope(command_stage, organization_id),
         {:ok, _mission} <-
           Missions.fetch_mission(
             scoped_command_stage.organization_id,
             scoped_command_stage.mission_id
           ),
         {:ok, %CommandStageRow{} = row} <-
           Repo.insert(CommandStageRow.changeset(scoped_command_stage),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :command_stage_id]
           ) do
      {:ok, CommandStageRow.to_domain(row)}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update_stage(binary(), CommandStage.t()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  def update_stage(organization_id, %CommandStage{} = command_stage)
      when is_binary(organization_id) do
    with {:ok, scoped_command_stage} <- put_organization_scope(command_stage, organization_id),
         {:ok, row} <-
           fetch_stage_row(
             scoped_command_stage.organization_id,
             scoped_command_stage.mission_id,
             scoped_command_stage.command_stage_id
           ),
         {:ok, %CommandStageRow{} = updated_row} <-
           row
           |> CommandStageRow.update_changeset(scoped_command_stage)
           |> Repo.update() do
      {:ok, CommandStageRow.to_domain(updated_row)}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_stage(binary(), binary(), binary()) ::
          {:ok, CommandStage.t()} | {:error, term()}
  def fetch_stage(organization_id, mission_id, command_stage_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(command_stage_id) do
    with {:ok, %CommandStageRow{} = row} <-
           fetch_stage_row(organization_id, mission_id, command_stage_id) do
      {:ok, CommandStageRow.to_domain(row)}
    end
  end

  @spec list_stages(binary(), binary(), keyword()) :: [CommandStage.t()]
  def list_stages(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    CommandStageRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_equals(:lifecycle_state, lifecycle_state_filter(opts))
    |> order_by([row], asc: row.inserted_at, asc: row.command_stage_id)
    |> Repo.all()
    |> Enum.map(&CommandStageRow.to_domain/1)
  end

  @spec persist_item(binary(), StagedCommandItem.t()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def persist_item(organization_id, %StagedCommandItem{} = staged_command_item)
      when is_binary(organization_id) do
    with {:ok, scoped_item} <- put_organization_scope(staged_command_item, organization_id),
         {:ok, _stage} <- validate_stage_assignment(scoped_item),
         {:ok, _source_endpoint} <-
           SourceEndpoints.fetch_source_endpoint(
             scoped_item.organization_id,
             scoped_item.mission_id,
             scoped_item.source_endpoint_ref
           ),
         {:ok, _request_basis} <-
           RequestValidation.resolve_basis(
             scoped_item.organization_id,
             scoped_item.mission_id,
             scoped_item.mission_model_revision_id,
             scoped_item.command_id
           ),
         {:ok, %StagedCommandItemRow{} = row} <-
           Repo.insert(StagedCommandItemRow.changeset(scoped_item),
             on_conflict: :nothing,
             conflict_target: [:mission_id, :staged_command_item_id]
           ) do
      {:ok, StagedCommandItemRow.to_domain(row)}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update_item(binary(), StagedCommandItem.t()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def update_item(organization_id, %StagedCommandItem{} = staged_command_item)
      when is_binary(organization_id) do
    with {:ok, scoped_item} <- put_organization_scope(staged_command_item, organization_id),
         {:ok, row} <-
           fetch_item_row(
             scoped_item.organization_id,
             scoped_item.mission_id,
             scoped_item.staged_command_item_id
           ),
         :ok <- LifecyclePolicy.ensure_staged_item_editable(row),
         {:ok, _stage} <- validate_stage_assignment(scoped_item),
         {:ok, _source_endpoint} <-
           SourceEndpoints.fetch_source_endpoint(
             scoped_item.organization_id,
             scoped_item.mission_id,
             scoped_item.source_endpoint_ref
           ),
         {:ok, _request_basis} <-
           RequestValidation.resolve_basis(
             scoped_item.organization_id,
             scoped_item.mission_id,
             scoped_item.mission_model_revision_id,
             scoped_item.command_id
           ),
         {:ok, %StagedCommandItemRow{} = updated_row} <-
           row
           |> StagedCommandItemRow.update_changeset(scoped_item)
           |> Repo.update() do
      {:ok, StagedCommandItemRow.to_domain(updated_row)}
    else
      {:error, %Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_item(binary(), binary(), binary()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def fetch_item(organization_id, mission_id, staged_command_item_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(staged_command_item_id) do
    with {:ok, %StagedCommandItemRow{} = row} <-
           fetch_item_row(organization_id, mission_id, staged_command_item_id) do
      {:ok, StagedCommandItemRow.to_domain(row)}
    end
  end

  @spec list_items(binary(), binary(), keyword()) :: [StagedCommandItem.t()]
  def list_items(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    StagedCommandItemRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id
    )
    |> maybe_filter_equals(:command_stage_id, Keyword.get(opts, :command_stage_id))
    |> maybe_filter_equals(:source_endpoint_ref, Keyword.get(opts, :source_endpoint_ref))
    |> maybe_filter_equals(:lifecycle_state, lifecycle_state_filter(opts))
    |> order_by([row], asc: row.item_order, asc: row.inserted_at, asc: row.staged_command_item_id)
    |> Repo.all()
    |> Enum.map(&StagedCommandItemRow.to_domain/1)
  end

  @spec submit_items(binary(), binary(), binary(), [binary()], map()) ::
          {:ok, [CommandRequest.t()]} | {:error, term()}
  def submit_items(
        organization_id,
        mission_id,
        command_stage_id,
        staged_command_item_ids,
        requested_by
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(command_stage_id) and
             is_list(staged_command_item_ids) and is_map(requested_by) do
    with {:ok, stage_row} <- fetch_stage_row(organization_id, mission_id, command_stage_id),
         :ok <- LifecyclePolicy.ensure_stage_editable(stage_row),
         {:ok, item_rows} <-
           fetch_submission_item_rows(
             organization_id,
             mission_id,
             command_stage_id,
             staged_command_item_ids
           ),
         {:ok, validated_requests} <- build_stage_requests(item_rows, requested_by) do
      multi =
        validated_requests
        |> Enum.reduce(Multi.new(), fn {item_row, request}, multi ->
          multi
          |> Multi.insert(
            {:command_request, request.command_request_id},
            CommandRequestRow.changeset(request)
          )
          |> Multi.update(
            {:staged_command_item, item_row.staged_command_item_id},
            StagedCommandItemRow.submission_changeset(item_row, request.command_request_id)
          )
        end)
        |> maybe_mark_stage_submitted(stage_row, staged_command_item_ids)

      case Repo.transaction(multi) do
        {:ok, _changes} ->
          {:ok, fetch_submitted_requests(validated_requests, organization_id, mission_id)}

        {:error, _operation, %Changeset{} = changeset, _changes_so_far} ->
          {:error, changeset}

        {:error, _operation, reason, _changes_so_far} ->
          {:error, reason}
      end
    end
  end

  defp fetch_submitted_requests(validated_requests, organization_id, mission_id) do
    Enum.map(validated_requests, fn {_row, request} ->
      fetch_submitted_request(
        organization_id,
        mission_id,
        request.command_request_id
      )
    end)
  end

  defp fetch_submitted_request(organization_id, mission_id, command_request_id) do
    CommandRequestRow
    |> Repo.get_by!(
      organization_id: organization_id,
      mission_id: mission_id,
      command_request_id: command_request_id
    )
    |> CommandRequestRow.to_domain()
  end

  defp maybe_mark_stage_submitted(
         %Multi{} = multi,
         %CommandStageRow{} = stage_row,
         submitted_item_ids
       ) do
    remaining_draft_count =
      StagedCommandItemRow
      |> where(
        [row],
        row.organization_id == ^stage_row.organization_id and
          row.mission_id == ^stage_row.mission_id and
          row.command_stage_id == ^stage_row.command_stage_id and
          row.lifecycle_state == "draft" and
          row.staged_command_item_id not in ^submitted_item_ids
      )
      |> select([row], count(row.staged_command_item_id))
      |> Repo.one()

    if remaining_draft_count == 0 do
      Multi.update(
        multi,
        :command_stage_submitted,
        CommandStageRow.lifecycle_changeset(stage_row, :submitted)
      )
    else
      multi
    end
  end

  defp build_stage_requests(item_rows, requested_by) do
    item_rows
    |> Enum.reduce_while({:ok, []}, fn %StagedCommandItemRow{} = item_row, {:ok, acc} ->
      request =
        CommandRequest.new(%{
          mission_id: item_row.mission_id,
          organization_id: item_row.organization_id,
          source_endpoint_ref: item_row.source_endpoint_ref,
          mission_model_revision_id: item_row.mission_model_revision_id,
          command_id: item_row.command_id,
          priority: item_row.priority,
          not_before: item_row.not_before,
          expires_at: item_row.expires_at,
          requested_by: requested_by,
          source_command_stage_id: item_row.command_stage_id,
          source_staged_command_item_id: item_row.staged_command_item_id,
          argument_values: JsonDocument.unwrap_value(item_row.argument_values_document),
          metadata: %{
            "notes" => item_row.notes,
            "stage_item_order" => item_row.item_order,
            "stage_item_metadata" => JsonDocument.unwrap_value(item_row.metadata_document)
          }
        })

      case RequestValidation.validate_and_enrich(request) do
        {:ok, validated_request} ->
          {:cont, {:ok, [{item_row, validated_request} | acc]}}

        {:error, reason} ->
          {:halt,
           {:error, {:staged_command_submission_failed, item_row.staged_command_item_id, reason}}}
      end
    end)
    |> case do
      {:ok, requests} -> {:ok, Enum.reverse(requests)}
      error -> error
    end
  end

  defp validate_stage_assignment(%StagedCommandItem{} = staged_command_item) do
    with {:ok, %CommandStage{} = command_stage} <-
           fetch_stage(
             staged_command_item.organization_id,
             staged_command_item.mission_id,
             staged_command_item.command_stage_id
           ),
         :ok <- LifecyclePolicy.ensure_stage_editable(command_stage) do
      {:ok, command_stage}
    end
  end

  defp fetch_stage_row(organization_id, mission_id, command_stage_id) do
    case Repo.get_by(CommandStageRow,
           organization_id: organization_id,
           mission_id: mission_id,
           command_stage_id: command_stage_id
         ) do
      nil -> {:error, :command_stage_not_found}
      %CommandStageRow{} = row -> {:ok, row}
    end
  end

  defp fetch_item_row(organization_id, mission_id, staged_command_item_id) do
    case Repo.get_by(StagedCommandItemRow,
           organization_id: organization_id,
           mission_id: mission_id,
           staged_command_item_id: staged_command_item_id
         ) do
      nil -> {:error, :staged_command_item_not_found}
      %StagedCommandItemRow{} = row -> {:ok, row}
    end
  end

  defp fetch_submission_item_rows(
         organization_id,
         mission_id,
         command_stage_id,
         staged_command_item_ids
       ) do
    normalized_ids =
      staged_command_item_ids
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    item_rows =
      StagedCommandItemRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.command_stage_id == ^command_stage_id and
          row.staged_command_item_id in ^normalized_ids
      )
      |> order_by([row], asc: row.item_order, asc: row.staged_command_item_id)
      |> Repo.all()

    cond do
      normalized_ids == [] ->
        {:error, :no_staged_command_items_selected}

      length(item_rows) != length(normalized_ids) ->
        found_ids = MapSet.new(Enum.map(item_rows, & &1.staged_command_item_id))

        missing_ids =
          normalized_ids
          |> Enum.reject(&MapSet.member?(found_ids, &1))
          |> Enum.sort()

        {:error, {:staged_command_items_not_found, missing_ids}}

      Enum.any?(item_rows, &(&1.lifecycle_state != "draft")) ->
        row = Enum.find(item_rows, &(&1.lifecycle_state != "draft"))

        {:error,
         {:staged_command_item_not_editable, row.staged_command_item_id, row.lifecycle_state}}

      true ->
        {:ok, item_rows}
    end
  end

  defp lifecycle_state_filter(opts) do
    case Keyword.get(opts, :lifecycle_state) do
      nil -> nil
      lifecycle_state when is_atom(lifecycle_state) -> Atom.to_string(lifecycle_state)
      lifecycle_state when is_binary(lifecycle_state) -> lifecycle_state
    end
  end

  defp maybe_filter_equals(query, _field, nil), do: query

  defp maybe_filter_equals(query, field, value) when is_atom(value) do
    where(query, [row], field(row, ^field) == ^Atom.to_string(value))
  end

  defp maybe_filter_equals(query, field, value) when is_binary(value) do
    where(query, [row], field(row, ^field) == ^value)
  end

  defp put_organization_scope(%CommandStage{} = command_stage, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case command_stage.organization_id do
      nil ->
        {:ok, %CommandStage{command_stage | organization_id: organization_id}}

      ^organization_id ->
        {:ok, command_stage}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          command_stage.mission_id}}
    end
  end

  defp put_organization_scope(%StagedCommandItem{} = staged_command_item, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case staged_command_item.organization_id do
      nil ->
        {:ok, %StagedCommandItem{staged_command_item | organization_id: organization_id}}

      ^organization_id ->
        {:ok, staged_command_item}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          staged_command_item.mission_id}}
    end
  end
end
