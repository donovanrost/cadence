defmodule Cadence.Control.ConfigurationSwitches do
  @moduledoc """
  Commanding and telemetry switches as change-set fields (L22, lead/api/fe-setup 2026-11-13).

  The spacecraft change-set kind stores them on the spacecraft (`commanding_enabled`,
  `telemetry_enabled`; nil = "as the configuration has it"). Like the catalog (#36/#65), the
  running configuration then follows them: an apply derives a configuration revision with the
  switches and rebuilds the generation (`Cadence.Control.ConfigurationGeneration`). Turning
  commanding off cancels the commands waiting to be sent to the spacecraft
  (`commanding_disabled`) and refuses while one is being sent; turning telemetry on needs the
  configuration's packet inputs.

  `impact/3` reads for the spacecraft kind's HOLDs; the rest is pure over the active fleet entries
  and the spacecraft records.
  """

  alias Cadence.Applications.ApplicationInstallations
  alias Cadence.Applications.SpacecraftConfiguration.Active
  alias Cadence.Commanding.RequestActivity
  alias Cadence.Missions
  alias Cadence.SourceEndpoints
  alias Cadence.SpacecraftStore

  @keys ~w(commanding_enabled telemetry_enabled)

  @doc """
  What an apply would do to the switches of `ids` (the L22 HOLDs): `%{commanding_off: [%{id,
  name, waiting: [request], in_flight: [request]}], telemetry_off: [%{id, name}],
  missing_inputs: [%{id, name}]}`.
  """
  @spec impact(binary(), binary(), [binary()]) :: map()
  def impact(organization_id, mission_id, ids) do
    entries = active_entries(organization_id, mission_id)

    {:ok, spacecraft} =
      SpacecraftStore.fetch_spacecrafts_in_batches(organization_id, mission_id, ids)

    targets = targets(spacecraft, entries)
    name = fn id -> spacecraft[id].display_name end

    %{
      commanding_off:
        Enum.map(commanding_off(targets), fn id ->
          endpoints = endpoints(organization_id, mission_id, id)

          %{
            id: id,
            name: name.(id),
            waiting: RequestActivity.waiting(organization_id, mission_id, endpoints),
            in_flight: RequestActivity.in_flight(organization_id, mission_id, endpoints)
          }
        end),
      telemetry_off: Enum.map(telemetry_off(targets), &%{id: &1, name: name.(&1)}),
      missing_inputs:
        for(
          id <- telemetry_on(targets),
          not packet_inputs?(entries[id]),
          do: %{id: id, name: name.(id)}
        ),
      not_installed:
        for(
          id <- not_installed(organization_id, mission_id, telemetry_on(targets)),
          do: %{id: id, name: name.(id)}
        )
    }
  end

  @doc """
  The spacecraft among `ids` without an installed telemetry app (one query). A Save installs it
  when telemetry turns on; a change set doesn't, because installing an application is its own
  governed act (director 11-15), so the preview holds and the apply refuses instead.
  """
  @spec not_installed(binary(), binary(), [binary()]) :: [binary()]
  def not_installed(_organization_id, _mission_id, []), do: []

  def not_installed(organization_id, mission_id, ids) do
    installed =
      ApplicationInstallations.configuration_bases(
        organization_id,
        mission_id,
        ids,
        "telemetry_decom"
      )

    Enum.reject(ids, fn id ->
      Enum.any?(Map.get(installed, id, []), fn {_id, _version, state} -> state == "installed" end)
    end)
  end

  defp active_entries(organization_id, mission_id) do
    with {:ok, mission} <- Missions.fetch_mission(organization_id, mission_id),
         {:ok, %{activation: %{}, entries: entries}} <- Active.load(mission) do
      entries
    else
      _no_active_activation -> %{}
    end
  end

  defp endpoints(organization_id, mission_id, spacecraft_id) do
    organization_id
    |> SourceEndpoints.list_source_endpoints(mission_id, spacecraft_id: spacecraft_id)
    |> Enum.map(& &1.source_endpoint_id)
  end

  @doc "The switch keys, as in the spacecraft kind document and the configuration document."
  def keys, do: @keys

  @doc "What the running configuration has: `%{\"commanding_enabled\" => bool, ...}`."
  @spec running(map() | nil) :: map()
  def running(entry) do
    document = (entry || %{})["document"] || %{}
    Map.new(@keys, &{&1, Map.get(document, &1, false) == true})
  end

  @doc """
  Spacecraft whose set switches differ from their running configuration:
  `%{spacecraft_id => %{key => value}}` (only the keys that change).
  """
  @spec targets(%{binary() => struct()}, map()) :: map()
  def targets(spacecraft, entries) do
    for {id, sc} <- spacecraft,
        entry = Map.get(entries, id),
        is_map(entry),
        changes = changes(sc, running(entry)),
        changes != %{},
        into: %{},
        do: {id, changes}
  end

  defp changes(sc, running) do
    for {key, set} <- [
          {"commanding_enabled", sc.commanding_enabled},
          {"telemetry_enabled", sc.telemetry_enabled}
        ],
        is_boolean(set) and set != running[key],
        into: %{},
        do: {key, set}
  end

  @doc "The spacecraft among `targets` turning commanding off."
  def commanding_off(targets),
    do: for({id, %{"commanding_enabled" => false}} <- targets, do: id)

  @doc "The spacecraft among `targets` turning telemetry off."
  def telemetry_off(targets),
    do: for({id, %{"telemetry_enabled" => false}} <- targets, do: id)

  @doc "The spacecraft among `targets` turning telemetry on."
  def telemetry_on(targets),
    do: for({id, %{"telemetry_enabled" => true}} <- targets, do: id)

  @doc """
  Telemetry can only be turned on when the configuration says which packets to decode and from
  where (the per-spacecraft review's own rule).
  """
  @spec packet_inputs?(map() | nil) :: boolean()
  def packet_inputs?(entry) do
    document = (entry || %{})["document"] || %{}

    document["handled_apids"] not in [nil, []] and
      is_binary(document["telemetry_source_endpoint_id"])
  end
end
