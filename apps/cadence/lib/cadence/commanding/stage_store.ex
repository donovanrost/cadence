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

  alias Cadence.Ids
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
           Repo.insert(CommandStageRow.changeset(scoped_command_stage)) do
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
    with {:ok, scoped} <- put_organization_scope(command_stage, organization_id) do
      with_locked_stage(
        organization_id,
        scoped.mission_id,
        scoped.command_stage_id,
        &update_locked_stage(&1, scoped)
      )
    end
  end

  defp update_locked_stage(row, stage) do
    with :ok <- LifecyclePolicy.ensure_stage_editable(row),
         :ok <- valid_stage_edit(row, stage),
         {:ok, updated} <- Repo.update(CommandStageRow.update_changeset(row, stage)) do
      {:ok, CommandStageRow.to_domain(updated)}
    end
  end

  defp valid_stage_edit(row, stage) do
    cond do
      stage.owner != JsonDocument.unwrap_value(row.owner_document) ->
        {:error, :command_stage_owner_immutable}

      stage.lifecycle_state not in [:draft, :in_review, :ready_to_submit, :canceled] ->
        {:error, :invalid_command_stage_transition}

      true ->
        :ok
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
    with {:ok, scoped} <- put_organization_scope(staged_command_item, organization_id) do
      with_locked_stage(
        organization_id,
        scoped.mission_id,
        scoped.command_stage_id,
        &persist_locked_item(&1, scoped)
      )
    end
  end

  defp persist_locked_item(stage, item) do
    with :ok <- LifecyclePolicy.ensure_stage_editable(stage),
         :ok <- valid_new_item(item),
         :ok <- validate_item_basis(item),
         {:ok, row} <- Repo.insert(StagedCommandItemRow.changeset(item)) do
      {:ok, StagedCommandItemRow.to_domain(row)}
    end
  end

  defp valid_new_item(%{lifecycle_state: :draft, submitted_command_request_id: nil}), do: :ok
  defp valid_new_item(_), do: {:error, :invalid_staged_command_initial_state}

  defp validate_item_basis(item) do
    with {:ok, _} <-
           SourceEndpoints.fetch_source_endpoint(
             item.organization_id,
             item.mission_id,
             item.source_endpoint_ref
           ),
         {:ok, _} <-
           RequestValidation.resolve_basis(
             item.organization_id,
             item.mission_id,
             item.mission_model_revision_id,
             item.command_id
           ) do
      :ok
    end
  end

  @spec update_item(binary(), StagedCommandItem.t()) ::
          {:ok, StagedCommandItem.t()} | {:error, term()}
  def update_item(organization_id, %StagedCommandItem{} = staged_command_item)
      when is_binary(organization_id) do
    with {:ok, scoped} <- put_organization_scope(staged_command_item, organization_id) do
      with_locked_stage(organization_id, scoped.mission_id, scoped.command_stage_id, fn stage ->
        update_locked_item(stage, scoped)
      end)
    end
  end

  defp update_locked_item(stage, item) do
    with :ok <- LifecyclePolicy.ensure_stage_editable(stage),
         {:ok, row} <-
           fetch_item_row(item.organization_id, item.mission_id, item.staged_command_item_id),
         :ok <- LifecyclePolicy.ensure_staged_item_editable(row),
         :ok <- valid_item_edit(row, item),
         :ok <- validate_item_edit_basis(row, item),
         {:ok, updated} <- Repo.update(StagedCommandItemRow.update_changeset(row, item)) do
      {:ok, StagedCommandItemRow.to_domain(updated)}
    end
  end

  defp validate_item_edit_basis(row, item) do
    current = StagedCommandItemRow.to_domain(row)
    fields = [:source_endpoint_ref, :mission_model_revision_id, :command_id, :argument_values]

    if Map.take(current, fields) == Map.take(item, fields),
      do: :ok,
      else: validate_item_basis(item)
  end

  defp valid_item_edit(row, item) do
    cond do
      row.command_stage_id != item.command_stage_id ->
        {:error, :staged_command_parent_immutable}

      item.submitted_command_request_id != row.submitted_command_request_id ->
        {:error, :staged_command_submission_immutable}

      item.lifecycle_state not in [:draft, :canceled] ->
        {:error, :invalid_staged_command_transition}

      true ->
        :ok
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
    with :ok <- valid_submission_ids(staged_command_item_ids) do
      with_locked_stage(organization_id, mission_id, command_stage_id, fn stage_row ->
        submit_locked(stage_row, staged_command_item_ids, requested_by)
      end)
    end
  end

  defp valid_submission_ids(ids) do
    if length(ids) in 1..25 and Enum.all?(ids, &Ids.valid_identifier?/1) and
         length(Enum.uniq(ids)) == length(ids),
       do: :ok,
       else: {:error, :invalid_staged_command_selection}
  end

  @doc "Reserves and resolves an exact finite batch without inserting formal requests."
  def preview_items(org, mission, stage_id, ids, actor) do
    with :ok <- valid_submission_ids(ids) do
      with_locked_stage(org, mission, stage_id, &preview_locked_items(&1, ids, actor))
    end
  end

  defp preview_locked_items(stage, ids, actor) do
    with :ok <- LifecyclePolicy.ensure_stage_editable(stage),
         {:ok, rows} <-
           fetch_submission_item_rows(
             stage.organization_id,
             stage.mission_id,
             stage.command_stage_id,
             ids
           ) do
      requests = Enum.map(rows, &build_stage_request(&1, actor))

      RequestValidation.with_authoring_requests(
        requests,
        :current,
        %{},
        &hold_batch(rows, &1, &2)
      )
    end
  end

  defp hold_batch(rows, validated, snapshot) do
    requests = Enum.map(validated, &elem(&1, 0))

    with :ok <- unexpired_requests(Enum.zip(rows, requests)) do
      {:ok,
       %{
         requests: requests,
         expected_basis: snapshot.token,
         targets:
           Map.new(validated, fn {request, state} ->
             {request.command_request_id, state.target_token}
           end),
         target_rows:
           Map.new(validated, fn {request, state} ->
             {request.command_request_id, state.target}
           end)
       }}
    end
  end

  @doc "Persists server-held batch semantics while the reviewed model and targets remain locked."
  def submit_reviewed_items(org, mission, stage_id, held, before_insert) do
    ids = Enum.map(held.requests, & &1.source_staged_command_item_id)

    with :ok <- valid_submission_ids(ids),
         true <-
           is_binary(held.expected_basis) and
             Enum.all?(held.requests, &is_binary(held.targets[&1.command_request_id])) do
      with_locked_stage(
        org,
        mission,
        stage_id,
        &submit_locked_review(&1, ids, held, before_insert)
      )
    else
      false -> {:error, :command_stage_changed}
      error -> error
    end
  end

  defp submit_locked_review(stage, ids, held, before_insert) do
    with :ok <- LifecyclePolicy.ensure_stage_editable(stage),
         {:ok, rows} <-
           fetch_submission_item_rows(
             stage.organization_id,
             stage.mission_id,
             stage.command_stage_id,
             ids
           ),
         true <- reviewed_intent_matches?(rows, held.requests) do
      revalidate_submission(stage, ids, rows, held, before_insert)
    else
      false -> {:error, :command_stage_changed}
      error -> error
    end
  end

  defp revalidate_submission(stage, ids, rows, held, before_insert) do
    RequestValidation.with_authoring_requests(
      held.requests,
      held.expected_basis,
      held.targets,
      fn validated, _ ->
        with true <- Enum.map(validated, &elem(&1, 0)) == held.requests,
             :ok <- before_insert.() do
          insert_validated_submission(stage, ids, rows, validated)
        else
          false -> {:error, :command_stage_changed}
          error -> error
        end
      end
    )
  end

  defp reviewed_intent_matches?(rows, requests) do
    fields =
      ~w(organization_id mission_id source_endpoint_ref mission_model_revision_id command_id argument_values priority not_before expires_at requested_by source_command_stage_id source_staged_command_item_id metadata)a

    length(rows) == length(requests) and
      Enum.all?(Enum.zip(rows, requests), fn {row, request} ->
        current = build_stage_request(row, request.requested_by)
        reviewed_intent = %{request | metadata: Map.delete(request.metadata, "validation_basis")}
        Map.take(current, fields) == Map.take(reviewed_intent, fields)
      end)
  end

  defp submit_locked(stage_row, item_ids, requested_by) do
    with :ok <- LifecyclePolicy.ensure_stage_editable(stage_row),
         {:ok, item_rows} <-
           fetch_submission_item_rows(
             stage_row.organization_id,
             stage_row.mission_id,
             stage_row.command_stage_id,
             item_ids
           ) do
      requests = Enum.map(item_rows, &build_stage_request(&1, requested_by))

      RequestValidation.with_authoring_requests(requests, :current, %{}, fn validated, _ ->
        insert_validated_submission(stage_row, item_ids, item_rows, validated)
      end)
    end
  end

  defp insert_validated_submission(stage, ids, item_rows, validated) do
    pairs = Enum.zip(item_rows, Enum.map(validated, fn {request, _} -> request end))
    with :ok <- unexpired_requests(pairs), do: insert_submission(stage, ids, pairs)
  end

  defp unexpired_requests(pairs) do
    Enum.reduce_while(pairs, :ok, fn {_, request}, :ok ->
      case LifecyclePolicy.ensure_request_not_expired(request) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp insert_submission(stage_row, item_ids, validated_requests) do
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
      |> maybe_mark_stage_submitted(stage_row, item_ids)

    case Repo.transaction(multi) do
      {:ok, _changes} ->
        {:ok,
         fetch_submitted_requests(
           validated_requests,
           stage_row.organization_id,
           stage_row.mission_id
         )}

      {:error, _operation, reason, _changes_so_far} ->
        {:error, reason}
    end
  end

  defp with_locked_stage(organization_id, mission_id, stage_id, operation) do
    Repo.transaction(fn ->
      case Repo.one(
             from(row in CommandStageRow,
               where:
                 row.organization_id == ^organization_id and row.mission_id == ^mission_id and
                   row.command_stage_id == ^stage_id,
               lock: "FOR UPDATE"
             )
           ) do
        nil -> Repo.rollback(:command_stage_not_found)
        row -> unwrap_locked(operation.(row))
      end
    end)
  end

  defp unwrap_locked({:ok, value}), do: value
  defp unwrap_locked({:error, reason}), do: Repo.rollback(reason)

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

  defp build_stage_request(item_row, requested_by) do
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
      |> where([row], fragment("octet_length(?::text)", row.argument_values_document) <= 32_768)
      |> where([row], fragment("octet_length(?::text)", row.metadata_document) <= 65_536)
      |> order_by([row], asc: row.item_order, asc: row.staged_command_item_id)
      |> lock("FOR UPDATE")
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
