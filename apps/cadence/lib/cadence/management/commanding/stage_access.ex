defmodule Cadence.Management.Commanding.StageAccess do
  @moduledoc "Fresh human stage access and the common stage-first transaction boundary."
  import Ecto.Query
  alias Cadence.Commanding.CommandStageRow
  alias Cadence.Ids
  alias Cadence.Management.Commanding.ReviewAccess
  alias Cadence.Repo

  defdelegate authorize(scope, mission), to: ReviewAccess

  # Visibility is applied in SQL before paging, including for organization admins.
  def visible_query(fresh, mission_id) do
    user_id = fresh.user.user_id

    from(row in CommandStageRow,
      where: row.organization_id == ^fresh.organization_id and row.mission_id == ^mission_id,
      where:
        row.visibility == "shared" or
          (row.visibility == "private" and
             fragment("? #>> '{value,user_id}'", row.owner_document) == ^user_id)
    )
  end

  def owner?(row, fresh),
    do: get_in(row.owner_document, ["value", "user_id"]) == fresh.user.user_id

  def with_stage(scope, mission_id, stage_id, mode, operation)
      when mode in [:read, :write] and is_function(operation, 3) do
    with {:ok, fresh, _} <- authorize(scope, mission_id),
         true <- Ids.valid_identifier?(stage_id) do
      Repo.transaction(fn -> locked(scope, fresh, mission_id, stage_id, mode, operation) end)
    else
      _ -> {:error, :unavailable}
    end
  end

  defp locked(scope, fresh, mission_id, stage_id, mode, operation) do
    query =
      fresh
      |> visible_query(mission_id)
      |> where([row], row.command_stage_id == ^stage_id)
      |> where([row], fragment("octet_length(?::text)", row.owner_document) <= 8_192)
      |> where([row], fragment("octet_length(?::text)", row.metadata_document) <= 65_536)
      |> where(
        [row],
        is_nil(row.description) or fragment("octet_length(?)", row.description) <= 4_000
      )

    query = if mode == :write, do: lock(query, "FOR UPDATE"), else: lock(query, "FOR SHARE")
    row = Repo.one(query)

    # The row lock may have waited behind a collaborator. Never use the authorization
    # snapshot from before that wait as authority for the returned data or effect.
    with %CommandStageRow{} <- row,
         {:ok, fresh, mission} <- authorize(scope, mission_id),
         true <-
           row.visibility == "shared" or (row.visibility == "private" and owner?(row, fresh)),
         {:ok, result} <- operation.(fresh, mission, row) do
      result
    else
      {:error, reason} -> Repo.rollback(reason)
      _ -> Repo.rollback(:unavailable)
    end
  end
end
