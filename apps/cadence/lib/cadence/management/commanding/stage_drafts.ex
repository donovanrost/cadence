defmodule Cadence.Management.Commanding.StageDrafts do
  @moduledoc "Finite human-owned stage creation and optimistic draft maintenance."
  import Ecto.Query

  alias Cadence.Commanding.{
    CommandStage,
    CommandStageRow,
    LifecyclePolicy,
    StagedCommandItemRow,
    StageStore
  }

  alias Cadence.Ids
  alias Cadence.Management.Commanding.{StageAccess, StageCatalog, StageInput}
  alias Cadence.Repo

  @states %{
    "draft" => :draft,
    "in_review" => :in_review,
    "ready_to_submit" => :ready_to_submit,
    "canceled" => :canceled
  }
  @visibility %{"private" => :private, "shared" => :shared}

  # Only the captured host session retains this value. It is never reconstructed
  # from a browser-supplied owner, durable ID or authorization claim.
  def prepare_create(scope, mission_id) do
    with {:ok, fresh, _} <- StageAccess.authorize(scope, mission_id) do
      {:ok,
       %{
         organization_id: fresh.organization_id,
         mission_id: mission_id,
         actor_id: fresh.user.user_id,
         stage_id: Ids.new("command_stage"),
         write_token: new_write_token()
       }}
    end
  end

  def new_write_token, do: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

  def create(scope, mission_id, held, input) when is_map(held) do
    with {:ok, fresh, _} <- StageAccess.authorize(scope, mission_id),
         {:ok, input} <- StageInput.create(input),
         true <-
           held.organization_id == fresh.organization_id and held.mission_id == mission_id and
             held.actor_id == fresh.user.user_id,
         :ok <- expected(input.expected_write, held.write_token) do
      stage =
        CommandStage.new(%{
          command_stage_id: held.stage_id,
          organization_id: fresh.organization_id,
          mission_id: mission_id,
          owner: %{"actor_kind" => "user", "user_id" => fresh.user.user_id},
          stage_name: String.trim(input.name),
          description: input.description,
          visibility: Map.fetch!(@visibility, input.visibility)
        })

      with {:ok, persisted} <- StageStore.persist_stage(fresh.organization_id, stage),
           do: {:ok, stage_receipt(persisted, fresh, "stage_created")}
    else
      false -> {:error, :unavailable}
      error -> error
    end
  end

  def edit_stage(scope, mission_id, stage_id, write_token, input) do
    with {:ok, input} <- StageInput.edit_stage(input),
         :ok <- expected(input.expected_write, write_token) do
      StageAccess.with_stage(scope, mission_id, stage_id, :write, fn fresh, _, row ->
        edit_locked_stage(fresh, row, input)
      end)
    end
  end

  defp edit_locked_stage(fresh, row, input) do
    with :ok <- expected(input.expected_stage, StageCatalog.stage_token(row)),
         true <- StageAccess.owner?(row, fresh),
         :ok <- LifecyclePolicy.ensure_stage_editable(row) do
      updated = %{
        CommandStageRow.to_domain(row)
        | stage_name: String.trim(input.name),
          description: input.description,
          visibility: Map.fetch!(@visibility, input.visibility),
          lifecycle_state: Map.fetch!(@states, input.state)
      }

      with {:ok, persisted} <- StageStore.update_stage(fresh.organization_id, updated),
           do: {:ok, stage_receipt(persisted, fresh, "stage_updated")}
    else
      false -> {:error, :unavailable}
      error -> error
    end
  end

  def edit_details(scope, mission_id, stage_id, item_id, write_token, input) do
    with {:ok, input} <- StageInput.edit_details(input) do
      maintain_item(scope, mission_id, stage_id, item_id, write_token, input,
        notes: input.notes,
        item_order: input.order
      )
    end
  end

  def cancel_item(scope, mission_id, stage_id, item_id, write_token, input) do
    with {:ok, input} <- StageInput.cancel_item(input) do
      maintain_item(scope, mission_id, stage_id, item_id, write_token, input,
        lifecycle_state: "canceled"
      )
    end
  end

  defp maintain_item(scope, mission_id, stage_id, item_id, write_token, input, changes) do
    with true <- Ids.valid_identifier?(item_id),
         :ok <- expected(input.expected_write, write_token) do
      StageAccess.with_stage(scope, mission_id, stage_id, :write, fn _fresh, _, stage ->
        maintain_locked_item(scope, stage, item_id, input, changes)
      end)
    else
      false -> {:error, :unavailable}
      error -> error
    end
  end

  defp maintain_locked_item(scope, stage, item_id, input, changes) do
    with :ok <- expected(input.expected_stage, StageCatalog.stage_token(stage)),
         :ok <- LifecyclePolicy.ensure_stage_editable(stage),
         {:ok, item} <- locked_item(stage, item_id),
         :ok <- expected(input.expected_item, item.token),
         :ok <- LifecyclePolicy.ensure_staged_item_editable(item),
         {:ok, fresh, _} <- StageAccess.authorize(scope, stage.mission_id) do
      persist_details(stage, item, fresh, changes)
    end
  end

  defp locked_item(stage, item_id) do
    case stage
         |> StageCatalog.item_query()
         |> where([row], row.staged_command_item_id == ^item_id)
         |> lock("FOR UPDATE")
         |> Repo.one() do
      nil -> {:error, :unavailable}
      row -> {:ok, row}
    end
  end

  defp persist_details(stage, item, fresh, changes) do
    query =
      from(row in StagedCommandItemRow,
        where:
          row.organization_id == ^fresh.organization_id and row.mission_id == ^stage.mission_id and
            row.command_stage_id == ^stage.command_stage_id and
            row.staged_command_item_id == ^item.staged_command_item_id
      )

    updated_at = DateTime.utc_now()
    {1, _} = Repo.update_all(query, set: Keyword.put(changes, :updated_at, updated_at))

    {:ok,
     %{
       "operation" =>
         if(changes[:lifecycle_state] == "canceled", do: "item_canceled", else: "item_updated"),
       "stage_id" => stage.command_stage_id,
       "item_id" => item.staged_command_item_id,
       "actor_id" => fresh.user.user_id,
       "updated_at" => DateTime.to_iso8601(updated_at)
     }}
  end

  defp expected(value, value) when is_binary(value), do: :ok
  defp expected(_, _), do: {:error, :command_stage_changed}

  defp stage_receipt(stage, fresh, operation),
    do: %{
      "operation" => operation,
      "stage_id" => stage.command_stage_id,
      "actor_id" => fresh.user.user_id,
      "name" => stage.stage_name,
      "visibility" => Atom.to_string(stage.visibility),
      "state" => Atom.to_string(stage.lifecycle_state)
    }
end
