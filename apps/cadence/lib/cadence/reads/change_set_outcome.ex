defmodule Cadence.Reads.ChangeSetOutcome do
  @moduledoc """
  What a staged change set would leave behind, for the explicit preview (#522, #313 K9;
  Changes.md K3's tiles). `Configuration.Preview.run/5` calls `reader/3`'s function before and
  after the staged ops inside its rolled-back transaction, and `shape/1` turns the two snapshots
  into the wire's `outcome`:

      %{spacecraft: %{now, after},
        routes: %{now, after, added, removed},
        readiness: %{now: counts, after: counts} | nil}

  - spacecraft: the mission's active (not archived) spacecraft.
  - routes: usable routes (comms_routing_rules rows, one per spacecraft: active and enabled) of
    active spacecraft, by id, so a set that swaps routes shows both added and removed.
  - readiness: Readiness' verdict counts (every severity but optional). They're read only when the
    set touches what Readiness reads (domain); otherwise nil. One evaluation at 500 spacecraft
    takes about 85 ms (measured 11-20).

  Only the explicit preview uses this, never the preview submit and review run as their gate
  (api-ops). The console's preview endpoints pass this module to `Control.Configuration.preview/4`
  (`outcome:`), so Control never depends on a read model (the plane rule).
  """

  alias Cadence.Comms.{RoutingRule, RoutingRuleStore}
  alias Cadence.Reads.Readiness
  alias Cadence.SpacecraftStore

  @readiness_kinds ~w(spacecraft spacecraft_profile spacecraft_override spacecraft_route
                      transport ground_station)

  # Kinds whose changes Readiness doesn't read (domain, #522): app configuration, and the derived
  # kinds the pipeline adds after the staged ops. Every registered kind is in one list or the
  # other (`ChangeSetOutcomeKindsTest`), so a new kind is classified on purpose.
  # Source endpoint relay declarations change allowed origins without affecting spacecraft readiness.
  @not_read_kinds ~w(derived_telemetry limit_definition monitoring_policy source_endpoint spacecraft_routes
                     framing_compatibility catalog_compatibility switch_compatibility
                     apid_compatibility)

  @doc "The kinds whose changes Readiness reads."
  @spec readiness_kinds() :: [String.t()]
  def readiness_kinds, do: @readiness_kinds

  @doc "The kinds whose changes Readiness doesn't read."
  @spec not_read_kinds() :: [String.t()]
  def not_read_kinds, do: @not_read_kinds

  @doc "Whether the set touches what Readiness reads."
  @spec readiness?([map()]) :: boolean()
  def readiness?(ops), do: Enum.any?(ops, &(Map.get(&1, :kind) in @readiness_kinds))

  @doc "The snapshot reader the preview calls before and after the ops."
  @spec reader(String.t(), String.t(), [map()]) :: (-> map())
  def reader(organization_id, mission_id, ops) do
    readiness? = readiness?(ops)
    fn -> snapshot(organization_id, mission_id, readiness?) end
  end

  @doc "The wire's `outcome` from the preview's `%{now, after}` snapshots (nil stays nil)."
  @spec shape(map() | nil) :: map() | nil
  def shape(%{now: now, after: later}) do
    %{
      spacecraft: %{now: now.spacecraft, after: later.spacecraft},
      routes: %{
        now: MapSet.size(now.routes),
        after: MapSet.size(later.routes),
        added: MapSet.size(MapSet.difference(later.routes, now.routes)),
        removed: MapSet.size(MapSet.difference(now.routes, later.routes))
      },
      readiness: readiness(now.readiness, later.readiness)
    }
  end

  def shape(_none), do: nil

  defp readiness(%{} = now, %{} = later), do: %{now: now, after: later}
  defp readiness(_now, _later), do: nil

  defp snapshot(organization_id, mission_id, readiness?) do
    active =
      organization_id
      |> SpacecraftStore.list_spacecraft(mission_id)
      |> MapSet.new(& &1.spacecraft_id)

    %{
      spacecraft: MapSet.size(active),
      # An archived spacecraft's routes don't count, whatever their own row says.
      routes:
        organization_id
        |> RoutingRuleStore.list_routing_rules(mission_id)
        |> Enum.filter(&(usable?(&1) and MapSet.member?(active, &1.spacecraft_id)))
        |> MapSet.new(& &1.routing_rule_id),
      readiness:
        if(readiness?,
          do:
            organization_id
            |> Readiness.evaluate(mission_id)
            |> Map.fetch!(:verdict)
            |> Map.delete(:optional)
        )
    }
  end

  # Readiness' own rule for a usable route.
  defp usable?(%RoutingRule{lifecycle_state: :active, enabled?: true}), do: true
  defp usable?(_rule), do: false
end
