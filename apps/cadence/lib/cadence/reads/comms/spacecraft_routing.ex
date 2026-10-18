defmodule Cadence.Reads.Comms.SpacecraftRouting do
  @moduledoc "Scoped Communications routing reads, independent of frontend delivery."
  alias Cadence.Applications.JSONBoundary
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Comms.{RoutingRuleStore, TransportStore}
  alias Cadence.{Ids, Missions, SpacecraftStore}

  def load(%Scope{mission_id: scoped_mission_id} = scope, mission_id, spacecraft_id)
      when is_nil(scoped_mission_id) or scoped_mission_id == mission_id do
    with {:ok, _} <- Ids.path_segment(mission_id),
         {:ok, _} <- Ids.path_segment(spacecraft_id),
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission_id
           }),
         {:ok, mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, spacecraft} <-
           SpacecraftStore.fetch_spacecraft(scope.organization_id, mission_id, spacecraft_id) do
      rules =
        RoutingRuleStore.list_routing_rules_for_spacecraft(
          scope.organization_id,
          mission_id,
          spacecraft_id
        )

      JSONBoundary.safe(%{"page" => page(mission, spacecraft, rules)})
    end
  rescue
    _exception -> {:error, :spacecraft_routing_unavailable}
  end

  def load(_scope, _mission_id, _spacecraft_id), do: {:error, :spacecraft_routing_unavailable}

  defp page(mission, spacecraft, rules) do
    base = "/missions/" <> segment(mission.mission_id)
    spacecraft_path = base <> "/spacecraft/" <> segment(spacecraft.spacecraft_id)

    %{
      "title" => "Comms Routing",
      "subtitle" =>
        "Durable routing rules that describe how this spacecraft uses mission transports.",
      "breadcrumbs" => [
        %{"label" => mission.display_name, "href" => base},
        %{"label" => "Spacecraft", "href" => base <> "/spacecraft"},
        %{"label" => spacecraft.display_name, "href" => spacecraft_path},
        %{"label" => "Routing", "href" => nil}
      ],
      "new_rule" => %{
        "id" => "new-spacecraft-routing-rule-link",
        "label" => "New Routing Rule",
        "href" => base <> "/comms/routing/new?spacecraft_id=" <> segment(spacecraft.spacecraft_id)
      },
      "empty_state" => %{
        "title" => "No routing rules",
        "description" =>
          "Create a routing rule when this spacecraft should use a mission transport."
      },
      "rules_id" => "spacecraft-routing-rules",
      "rows" => Enum.map(rules, &row(&1, mission, base))
    }
  end

  defp row(rule, mission, base) do
    transport_name =
      case TransportStore.fetch_transport_version(
             mission.organization_id,
             mission.mission_id,
             rule.transport_id,
             rule.transport_version
           ) do
        {:ok, transport} -> transport.display_name
        {:error, _} -> rule.transport_id
      end

    %{
      "id" => "spacecraft-routing-rule-" <> rule.routing_rule_id,
      "purpose_label" => rule.purpose_label,
      "display_name" => rule.display_name,
      "direction" => rule.direction |> to_string() |> String.upcase(),
      "transport_name" => transport_name,
      "transport_version" => rule.transport_version,
      "role" => rule.role |> to_string() |> String.upcase(),
      "state" => if(rule.enabled?, do: "ENABLED", else: "DISABLED"),
      "href" => base <> "/comms/routing/" <> segment(rule.routing_rule_id)
    }
  end

  defp segment(id) do
    {:ok, safe} = Ids.path_segment(id)
    URI.encode(safe, &URI.char_unreserved?/1)
  end
end
