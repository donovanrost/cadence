defmodule Cadence.Comms.ConfigKinds.SpacecraftRoutes do
  @moduledoc """
  Derived change-set kind: a spacecraft's profile routes (DECISIONS #3).

  Routes aren't staged directly. They follow from profile routing rules, spacecraft pins,
  overrides, stations and transports. `finalize/3` runs after every other op of a change set,
  works out which spacecraft those ops affect, re-materializes their routes, and returns one
  ledger entry per spacecraft whose routes changed. Booked and running contacts keep the routes
  they were booked with, so the after-commit tail notifies the contact scheduler.
  """

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.Comms.RouteMaterializer
  alias Cadence.Platform.ConfigFields, as: F
  alias Cadence.SpacecraftStore

  @impl true
  def kind, do: "spacecraft_routes"

  @impl true
  def id_prefix, do: "spacecraft"

  @impl true
  def load(organization_id, mission_id, ids),
    do: Map.new(ids, &{&1, RouteMaterializer.document(organization_id, mission_id, &1)})

  @impl true
  def normalize(_action, _id, _document),
    do: {:error, [F.error("", "Routes come from profile rules; edit the profile or an override")]}

  @impl true
  def validate(_organization_id, _mission_id, _action, _entity_id, _previous, _proposed), do: :ok

  @impl true
  def write(_organization_id, _mission_id, _action, _id, _previous, _proposed, _options),
    do: {:error, :routes_are_derived}

  @impl true
  def summary(_action, _previous, _proposed), do: "Routes regenerated"

  @impl true
  def runtime_impact(_action, _previous, _proposed), do: :contacts

  @impl true
  def finalize(organization_id, mission_id, entries) do
    ids = affected(organization_id, mission_id, entries)

    case RouteMaterializer.materialize(organization_id, mission_id, ids) do
      {:ok, []} ->
        {:ok, [], []}

      {:ok, changes} ->
        {:ok,
         Enum.map(changes, fn change ->
           %{
             kind: kind(),
             entity_id: change.spacecraft_id,
             op: :update,
             previous: change.previous,
             proposed: change.proposed
           }
         end), [:contacts]}

      {:error, errors} ->
        {:error, errors}
    end
  end

  # Which spacecraft a set of entries can change the routes of.
  defp affected(organization_id, mission_id, entries) do
    if Enum.any?(entries, &(&1.kind in ["transport", "ground_station"])) do
      organization_id
      |> SpacecraftStore.list_spacecraft(mission_id)
      |> Enum.reject(&is_nil(&1.spacecraft_type_id))
      |> Enum.map(& &1.spacecraft_id)
    else
      entries
      |> Enum.flat_map(&spacecraft_of(organization_id, mission_id, &1))
      |> Enum.uniq()
    end
  end

  defp spacecraft_of(_org, _mission, %{kind: kind, entity_id: id})
       when kind in ["spacecraft", "spacecraft_override"],
       do: [id]

  defp spacecraft_of(org, mission, %{kind: "spacecraft_profile", entity_id: id}),
    do: org |> SpacecraftStore.list_pinned_to_profile(mission, id) |> Enum.map(& &1.spacecraft_id)

  defp spacecraft_of(_org, _mission, _entry), do: []
end
