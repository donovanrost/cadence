defmodule Cadence.Contacts.BookingResolutions.Attention do
  @moduledoc """
  The `pass_resolution` source of the mission attention read (DECISIONS #54): conflicts left
  by resolving unconfirmed bookings, and the operator actions on them (acknowledge, resolve).
  The shape is the one every attention source gives `Cadence.Reads.Attention`.
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Contacts.BookingResolutions
  alias Cadence.Contacts.BookingResolutions.Row
  alias Cadence.Repo

  @source "pass_resolution"
  @live ~w(open acknowledged)

  def source, do: @source

  @doc "Open and acknowledged conflicts, soonest pass first."
  @spec items(binary(), binary()) :: [map()]
  def items(org, mission) do
    Row
    |> where([r], r.organization_id == ^org and r.mission_id == ^mission)
    |> where([r], r.conflict_state in ^@live)
    |> order_by([r], asc: r.starts_at, asc: r.booking_resolution_id)
    |> Repo.all()
    |> Enum.map(&item/1)
  end

  @doc "Conflicts resolved since `since`, with who or what resolved them."
  @spec resolved_since(binary(), binary(), DateTime.t()) :: [map()]
  def resolved_since(org, mission, %DateTime{} = since) do
    Row
    |> where([r], r.organization_id == ^org and r.mission_id == ^mission)
    |> where([r], r.conflict_state == "resolved" and r.conflict_resolved_at >= ^since)
    |> order_by([r], desc: r.conflict_resolved_at)
    |> Repo.all()
    |> Enum.map(fn row ->
      %{
        id: row.booking_resolution_id,
        source: @source,
        resolved_by: row.conflict_resolved_by,
        action: row.conflict_resolution_action,
        resolved_at: row.conflict_resolved_at
      }
    end)
  end

  @doc "`%{open: n, acknowledged: n}` in one grouped query."
  @spec counts(binary(), binary()) :: %{open: non_neg_integer(), acknowledged: non_neg_integer()}
  def counts(org, mission) do
    counts =
      Row
      |> where([r], r.organization_id == ^org and r.mission_id == ^mission)
      |> where([r], r.conflict_state in ^@live)
      |> group_by([r], r.conflict_state)
      |> select([r], {r.conflict_state, count(r.booking_resolution_id)})
      |> Repo.all()
      |> Map.new()

    %{open: Map.get(counts, "open", 0), acknowledged: Map.get(counts, "acknowledged", 0)}
  end

  @doc "Acknowledges an open conflict: it stays listed, sorted last, until resolved."
  @spec acknowledge(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def acknowledge(%Scope{} = scope, mission, id) do
    transition(scope, mission, id, ["open"], fn actor ->
      %{
        conflict_state: "acknowledged",
        conflict_acknowledged_at: DateTime.utc_now(),
        conflict_acknowledged_by: actor
      }
    end)
  end

  @doc "Resolves a conflict by hand (the operator dealt with it); `action` says how."
  @spec resolve(Scope.t(), binary(), binary(), String.t()) :: {:ok, map()} | {:error, term()}
  def resolve(%Scope{} = scope, mission, id, action) when is_binary(action) and action != "" do
    transition(scope, mission, id, @live, fn actor ->
      %{
        conflict_state: "resolved",
        conflict_resolved_at: DateTime.utc_now(),
        conflict_resolved_by: actor,
        conflict_resolution_action: String.slice(action, 0, 200)
      }
    end)
  end

  def resolve(_scope, _mission, _id, _action), do: {:error, {:invalid, %{action: "is required"}}}

  defp transition(scope, mission, id, from, attrs) do
    with {:ok, actor} <- actor(scope, mission),
         %Row{} = row <-
           Repo.get_by(Row,
             organization_id: scope.organization_id,
             mission_id: mission,
             booking_resolution_id: id
           ) || {:error, :attention_item_not_found},
         true <- row.conflict_state in from || {:error, :attention_item_not_open},
         {:ok, row} <- row |> Row.state_changeset(attrs.(actor)) |> Repo.update() do
      BookingResolutions.changed(row.organization_id, row.mission_id)
      {:ok, item(row)}
    end
  end

  defp actor(%Scope{user: %{user_id: id, display_name: name}} = scope, mission) do
    with :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }),
         do: {:ok, %{"kind" => "user", "id" => id, "name" => name}}
  end

  defp actor(_scope, _mission), do: {:error, :forbidden}

  defp item(%Row{} = row) do
    %{
      id: row.booking_resolution_id,
      source: @source,
      conflict: row.conflict,
      state: row.conflict_state,
      acknowledged_by: row.conflict_acknowledged_by,
      spacecraft_id: row.spacecraft_id,
      contact_id: row.scheduled_contact_id,
      provider_reservation_id: row.provider_reservation_id,
      provider_contact_ref: row.provider_contact_ref,
      ground_station_ref: row.ground_station_ref,
      provider_id: row.provider_id,
      starts_at: row.starts_at,
      ends_at: row.ends_at,
      raised_at: row.conflict_raised_at,
      provider_message: row.conflict_document["provider_message"],
      resolution: %{
        action: row.action,
        actor: row.actor_document,
        at: row.inserted_at,
        note: row.note,
        provider_reference: row.provider_reference
      }
    }
  end
end
