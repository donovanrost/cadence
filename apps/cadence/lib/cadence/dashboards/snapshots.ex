defmodule Cadence.Dashboards.Snapshots do
  @moduledoc """
  Console snapshot writes (DECISIONS #76 Q5/Q6, D16): take a snapshot with a frozen window, and
  delete one.

  A console snapshot always freezes its window (Q5): `runtime` needs `from` before `to` (ISO 8601
  UTC). Delete leaves a tombstone, so the snapshot's own link says it was deleted rather than a
  bare not-found; no share points at a snapshot, so there's nothing else to revoke. Deletes are
  audited.
  """

  import Ecto.Query

  alias Cadence.Auth.Scope

  alias Cadence.Dashboards.{
    Authoring,
    AuthoringInput,
    ConfigAudit,
    DashboardSnapshot,
    Management,
    SettingsStore
  }

  alias Cadence.Dashboards.DocumentStore.DashboardRow
  alias Cadence.Repo

  @visibility ~w(authorized_runtime_data definition_only)

  @doc """
  `input`: `%{"data_visibility", "runtime" => %{"from", "to", "spacecraft_id" | nil}}`.
  `{:ok, snapshot}` or `{:error, :forbidden | :not_found | {:invalid, %{field => message}}}`.
  """
  def create(%Scope{} = scope, mission, dashboard_id, input) do
    with :ok <- Authoring.authorize(scope, mission),
         {:ok, visibility, runtime} <- admit(input) do
      scope.organization_id
      |> SettingsStore.with_dashboard(
        mission,
        dashboard_id,
        :read,
        &take(scope, &1, runtime, visibility)
      )
      |> created()
    end
  end

  defp take(scope, row, runtime, visibility) do
    case Management.create_snapshot(
           scope.organization_id,
           row.mission_id,
           DashboardRow.to_document(row),
           runtime,
           created_by: scope.user.user_id,
           data_visibility: visibility
         ) do
      {:ok, snapshot} -> snapshot
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp created({:ok, snapshot}), do: {:ok, snapshot}

  defp created({:error, reason}) when reason in [:unavailable, :dashboard_not_found],
    do: {:error, :not_found}

  defp created({:error, %Ecto.Changeset{}}),
    do: {:error, {:invalid, %{"" => "Check the snapshot"}}}

  defp created({:error, reason}), do: {:error, reason}

  @doc "Deletes a snapshot, leaving a tombstone. `:ok` or `{:error, :forbidden | :not_found}`."
  def delete(%Scope{} = scope, mission, snapshot_id) do
    with :ok <- Authoring.authorize(scope, mission),
         {:ok, :ok} <- Repo.transaction(fn -> tombstone(scope, mission, snapshot_id) end),
         do: :ok
  end

  defp tombstone(scope, mission, snapshot_id) do
    snapshot =
      from(s in DashboardSnapshot,
        where:
          s.organization_id == ^scope.organization_id and s.mission_id == ^mission and
            s.dashboard_snapshot_id == ^snapshot_id and is_nil(s.deleted_at),
        lock: "FOR UPDATE"
      )
      |> Repo.one()

    if is_nil(snapshot), do: Repo.rollback(:not_found)

    snapshot
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(), deleted_by: scope.user.user_id)
    |> Repo.update!()

    ConfigAudit.record(scope, mission, :snapshot_deleted, %{
      kind: "snapshot",
      id: snapshot_id,
      label: dashboard_name(scope.organization_id, mission, snapshot.dashboard_id)
    })
  end

  defp admit(%{"data_visibility" => visibility, "runtime" => runtime} = input)
       when map_size(input) == 2 and is_map(runtime) do
    with :ok <- visibility(visibility),
         {:ok, from} <- time(runtime["from"], "runtime.from", "Choose when the snapshot starts"),
         {:ok, to} <- time(runtime["to"], "runtime.to", "Choose when the snapshot ends"),
         :ok <- ordered(from, to),
         {:ok, spacecraft_id} <- spacecraft(runtime["spacecraft_id"]),
         [] <- Map.keys(runtime) -- ~w(from to spacecraft_id) do
      {:ok, visibility,
       %{
         "from" => DateTime.to_iso8601(from),
         "to" => DateTime.to_iso8601(to),
         "spacecraft_id" => spacecraft_id
       }}
    else
      {:error, _invalid} = error -> error
      _extra -> {:error, {:invalid, %{"runtime" => "Send from, to and spacecraft_id only"}}}
    end
  end

  defp admit(_input),
    do: {:error, {:invalid, %{"" => "Send data_visibility and runtime {from, to}"}}}

  defp visibility(value) when value in @visibility, do: :ok

  defp visibility(_value),
    do: {:error, {:invalid, %{"data_visibility" => "Choose definition only or with data"}}}

  defp time(value, field, message) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, 0} -> {:ok, at}
      _invalid -> {:error, {:invalid, %{field => message}}}
    end
  end

  defp time(_value, field, message), do: {:error, {:invalid, %{field => message}}}

  defp ordered(from, to) do
    if DateTime.before?(from, to),
      do: :ok,
      else: {:error, {:invalid, %{"runtime.to" => "End after the start"}}}
  end

  defp spacecraft(nil), do: {:ok, nil}

  defp spacecraft(id) when is_binary(id),
    do: if(AuthoringInput.id?(id), do: {:ok, id}, else: bad_spacecraft())

  defp spacecraft(_id), do: bad_spacecraft()

  defp bad_spacecraft,
    do: {:error, {:invalid, %{"runtime.spacecraft_id" => "Choose a spacecraft or none"}}}

  defp dashboard_name(organization_id, mission_id, dashboard_id) do
    from(d in DashboardRow,
      where:
        d.organization_id == ^organization_id and d.mission_id == ^mission_id and
          d.dashboard_id == ^dashboard_id,
      select: d.name
    )
    |> Repo.one()
    |> Kernel.||(dashboard_id)
  end
end
