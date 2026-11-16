defmodule Cadence.Comms.ConfigKinds.LegacyRoutingRule do
  @moduledoc """
  Change-set kind for removing an older (legacy) per-spacecraft routing rule (director 11-16).
  DELETE ONLY: legacy routing only shrinks (#80); the way to route somewhere is an extra route
  (`spacecraft_route`). It's how a legacy rule the conversion can't map leaves, staged, reviewed
  and recorded like any change. Not temporary: it stays while any legacy rule can exist and is
  inert once a mission has none.

  Document (read-only, for previews and history): `%{"spacecraft_id", "display_name",
  "purpose_label", "direction", "role", "transport_id"}` of an ACTIVE legacy rule of the mission.

  Refusals use ux's words (U79), never an id: a rule the conversion already replaced, "This route
  was converted already. Remove it as an extra route."; anything else that isn't an active legacy
  rule of this mission, "This rule can't be removed here." Both refuse at stage
  (`absent_errors/3`) and again at validate.

  Rollback (lead, (i)): a rollback that would re-create a removed rule gets a NO-GO validation item
  ("The older route … was removed and can't be restored. To route that way again, add an extra
  route."). Creates pass normalize only so the rollback preview can show that item; they never
  apply.
  """

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.Comms.RoutingRuleStore
  alias Cadence.Platform.ConfigFields, as: F
  alias Cadence.SpacecraftStore

  @converted "This route was converted already. Remove it as an extra route."
  @not_removable "This rule can't be removed here."

  @impl true
  def kind, do: "legacy_routing_rule"

  @impl true
  def id_prefix, do: "routing_rule"

  @impl true
  def load(organization_id, mission_id, ids) do
    for id <- ids,
        {:ok, rule} <- [RoutingRuleStore.fetch_routing_rule(organization_id, mission_id, id)],
        removable?(rule, mission_id),
        into: %{},
        do: {id, document(rule)}
  end

  @impl true
  def normalize(:delete, _id, nil), do: {:ok, nil}

  # Only a rollback stages a create (to restore a removed rule); validate refuses it with ux's words.
  def normalize(:create, _id, %{} = document), do: {:ok, document}

  def normalize(_action, _id, _document),
    do: {:error, [F.error("", "Older routes can only be removed.")]}

  @impl true
  def absent_errors(organization_id, mission_id, id),
    do: [F.error("", refusal(organization_id, mission_id, id))]

  @impl true
  def validate(organization_id, mission_id, :delete, id, _previous, nil) do
    case RoutingRuleStore.fetch_routing_rule(organization_id, mission_id, id) do
      {:ok, rule} ->
        if removable?(rule, mission_id), do: :ok, else: absent(organization_id, mission_id, id)

      _missing ->
        absent(organization_id, mission_id, id)
    end
  end

  def validate(organization_id, mission_id, :create, _id, _previous, document),
    do: {:error, [F.error("", not_restorable(organization_id, mission_id, document))]}

  def validate(_organization_id, _mission_id, _action, _id, _previous, _document),
    do: {:error, [F.error("", "Older routes can only be removed.")]}

  @impl true
  def write(organization_id, mission_id, :delete, id, _previous, nil, _options) do
    case RoutingRuleStore.archive_routing_rule(organization_id, mission_id, id) do
      {:ok, _archived} -> {:ok, nil, []}
      {:error, reason} -> {:error, reason}
    end
  end

  def write(_organization_id, _mission_id, _action, _id, _previous, _proposed, _options),
    do: {:error, [F.error("", "Older routes can only be removed.")]}

  @impl true
  def summary(_action, previous, _proposed),
    do: "Remove older route #{inspect((previous || %{})["display_name"])}"

  @impl true
  def runtime_impact(_action, _previous, _proposed), do: :contacts

  defp absent(organization_id, mission_id, id),
    do: {:error, absent_errors(organization_id, mission_id, id)}

  defp removable?(rule, mission_id),
    do:
      rule.origin == :legacy and rule.lifecycle_state == :active and rule.mission_id == mission_id

  # The conversion archived it and an extra route says it replaced it.
  defp refusal(organization_id, mission_id, id) do
    converted? =
      organization_id
      |> RoutingRuleStore.list_routing_rules(mission_id)
      |> Enum.any?(&(id in List.wrap((&1.metadata || %{})["converted_from"])))

    if converted?, do: @converted, else: @not_removable
  end

  # ux U79: 'The older route “<name>” · <spacecraft> was removed and can't be restored. To route
  # that way again, add an extra route.'
  defp not_restorable(organization_id, mission_id, document) do
    craft =
      case SpacecraftStore.fetch_spacecraft(
             organization_id,
             mission_id,
             document["spacecraft_id"]
           ) do
        {:ok, %{display_name: name}} when is_binary(name) -> name
        _unknown -> nil
      end

    "The older route#{route_words(document["display_name"], craft)} was removed and can't be " <>
      "restored. To route that way again, add an extra route."
  end

  # ux U79: named, ' “<name>” · <craft>'; unnamed, ' for <craft>'; neither, nothing.
  defp route_words(name, craft) when is_binary(name) and is_binary(craft),
    do: " “#{name}” · #{craft}"

  defp route_words(name, nil) when is_binary(name), do: " “#{name}”"
  defp route_words(nil, craft) when is_binary(craft), do: " for #{craft}"
  defp route_words(_name, _craft), do: ""

  defp document(rule),
    do: %{
      "spacecraft_id" => rule.spacecraft_id,
      "display_name" => rule.display_name,
      "purpose_label" => rule.purpose_label,
      "direction" => Atom.to_string(rule.direction),
      "role" => Atom.to_string(rule.role),
      "transport_id" => rule.transport_id
    }
end
