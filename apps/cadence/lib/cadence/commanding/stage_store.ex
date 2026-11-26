defmodule Cadence.Commanding.StageStore do
  @moduledoc """
  Persists command stages and staged items.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Commanding.{
    CommandStage,
    CommandStageRow,
    LifecyclePolicy,
    RequestValidation,
    StagedCommandItem,
    StagedCommandItemRow
  }

  alias Cadence.Missions
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Platform.ScopedReadUpdates, as: ReadUpdates
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
      ReadUpdates.publish_result(
        {:ok, CommandStageRow.to_domain(row)},
        :commanding_changed,
        row.organization_id,
        row.mission_id
      )
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
      |> ReadUpdates.publish_result(:commanding_changed, organization_id, scoped.mission_id)
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
      |> ReadUpdates.publish_result(:commanding_changed, organization_id, scoped.mission_id)
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
             item.command_id,
             item.source_endpoint_ref
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
      |> ReadUpdates.publish_result(:commanding_changed, organization_id, scoped.mission_id)
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
