defmodule Cadence.Control.LimitDefinitionKind do
  @moduledoc """
  Change-set kind for limit definitions (DECISIONS #77, stage 2).

  One entity per point and limit set (id = its limit definition id). The document is
  `{point_id, limit_set_name, thresholds: {red_low, yellow_low, yellow_high, red_high}, metadata}`.
  Create and update append the next version and make it active; delete **retires** the limits:
  evaluation stops, the versions stay, and creating the same point and set later continues the
  history.

  Writes run with facts held back: a change set announces limit changes to alarms and dashboards
  only after it commits (`after_commit/3`), so a preview or a discarded change set announces
  nothing. The ops-console direct save keeps announcing as it always has (#77 decisions 1 and 2
  are the user's).

  Acknowledge HOLD `limit_alarm_active` (ux U43) when the point's limit alarm is raised now.

  Control plane: limits and alarms are data plane, derived points management.
  """

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.Alarms.Queries, as: Alarms
  alias Cadence.Governance
  alias Cadence.Limits
  alias Cadence.Limits.Definition
  alias Cadence.Platform.ConfigFields, as: F

  @fields ~w(point_id limit_set_name thresholds metadata)
  @thresholds ~w(red_low yellow_low yellow_high red_high)

  @impl true
  def kind, do: "limit_definition"

  @impl true
  def id_prefix, do: "limit_definition"

  @doc "A limit definition's id is its point and limit set's, across versions and retires."
  @impl true
  def create_entity_id(document),
    do: Limits.limit_definition_id(document["point_id"], document["limit_set_name"])

  @impl true
  def load(organization_id, mission_id, ids) do
    organization_id
    |> Limits.active_limit_definitions(mission_id)
    |> Enum.filter(&(&1.limit_definition_id in ids))
    |> Map.new(&{&1.limit_definition_id, document(&1)})
  end

  @impl true
  def normalize(:delete, _id, nil), do: {:ok, nil}

  def normalize(_action, _id, %{} = document) do
    document =
      document
      |> Map.put_new("limit_set_name", "DEFAULT")
      |> Map.put_new("thresholds", %{})
      |> Map.put_new("metadata", %{})

    errors =
      F.only(document, @fields) ++
        F.text(document, "point_id", 1..240, required: true, label: "Point ID") ++
        F.text(document, "limit_set_name", 1..120, required: true, label: "Limit set") ++
        F.map(document, "metadata") ++ threshold_errors(document["thresholds"])

    F.result(document, errors)
  end

  def normalize(_action, _id, _document),
    do: {:error, [F.error("", "Enter the point and its limits")]}

  @impl true
  def validate(_organization_id, _mission_id, :delete, _id, _previous, nil), do: :ok

  def validate(org, mission_id, action, id, previous, proposed) do
    errors =
      identity_errors(org, mission_id, action, {id, previous}, proposed) ++
        point_errors(org, mission_id, proposed)

    if errors == [], do: :ok, else: {:error, errors}
  end

  @impl true
  def write(organization_id, mission_id, :delete, id, _previous, nil, _options) do
    # The live version itself, so the retired event names its real id and version.
    with %Definition{} = live <-
           organization_id
           |> Limits.active_limit_definitions(mission_id)
           |> Enum.find(
             {:error, :active_limit_definition_not_found},
             &(&1.limit_definition_id == id)
           ),
         {:ok, _event} <-
           Limits.retire_limit_definition(organization_id, mission_id, live,
             publish_facts?: false
           ) do
      {:ok, nil, []}
    end
  end

  def write(organization_id, mission_id, _action, _id, _previous, proposed, _options) do
    point = proposed["point_id"]
    set = proposed["limit_set_name"]
    review = Limits.limit_definition_review(organization_id, mission_id, point, set)

    organization_id
    |> Limits.append_limit_definition(
      mission_id,
      %{
        point_id: point,
        limit_set_name: set,
        thresholds: proposed["thresholds"] || %{},
        metadata: proposed["metadata"] || %{}
      },
      review,
      publish_facts?: false
    )
    |> case do
      {:ok, %Definition{} = stored} -> {:ok, document(stored), []}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def summary(:create, nil, proposed), do: "Add limits for #{label(proposed)}"
  def summary(:delete, previous, nil), do: "Retire limits for #{label(previous)}"
  def summary(:update, previous, _proposed), do: "Edit limits for #{label(previous)}"

  @impl true
  def runtime_impact(_action, _previous, _proposed), do: :none

  @doc "After the change set commits: announce the changed limits to alarms and dashboards."
  @impl true
  def after_commit(organization_id, mission_id, entries) do
    definitions =
      for entry <- entries, document = entry.proposed || entry.previous, document != nil do
        definition(document)
      end

    Limits.announce_limit_definitions(organization_id, mission_id, definitions)
  end

  @doc "Acknowledge HOLD (ux U43): the point's limit alarm is raised now."
  @impl true
  def holds(_organization_id, mission_id, entries) do
    for %{kind: "limit_definition"} = entry <- entries,
        document = entry.proposed || entry.previous,
        document != nil,
        episode <- raised(mission_id, document["point_id"]) do
      %{
        op_id: nil,
        change_id: nil,
        kind: kind(),
        entity_id: entry.entity_id,
        reason: :limit_alarm_active,
        blocking: false,
        sentence: alarm_sentence(entry.op, document["point_id"], episode.severity),
        details: %{
          point_id: document["point_id"],
          limit_set_name: document["limit_set_name"],
          severity: episode.severity,
          episode_id: episode.episode_id
        }
      }
    end
  end

  defp raised(mission_id, point_id),
    do: mission_id |> Alarms.active_limit_alarms(point_id) |> Enum.take(1)

  # Placeholder until ux's U43 wording lands.
  defp alarm_sentence(:delete, point, severity),
    do: "#{point}'s #{severity} alarm is raised now: retiring these limits clears it."

  defp alarm_sentence(_op, point, severity),
    do:
      "#{point}'s #{severity} alarm is raised now: applying this re-evaluates it against the new limits."

  defp identity_errors(_org, _mission, :update, {_id, previous}, proposed) do
    if previous["point_id"] == proposed["point_id"] and
         previous["limit_set_name"] == proposed["limit_set_name"],
       do: [],
       else: [F.error("point_id", "Retire these limits and add new ones to move them")]
  end

  # A create staged with its own entity id must still name its point and set's id (a second
  # create of live limits is the change set's entity_exists conflict).
  defp identity_errors(_org, _mission, :create, {id, _previous}, proposed) do
    if id == create_entity_id(proposed),
      do: [],
      else: [F.error("point_id", "This id isn't the point and limit set's")]
  end

  defp point_errors(org, mission, proposed) do
    point = proposed["point_id"]

    known? =
      MapSet.member?(catalog_points(org, mission), point) or
        Enum.any?(Governance.list_derived_definitions(org, mission), &(&1.point_id == point))

    if known?, do: [], else: [F.error("point_id", "Unknown point #{point}")]
  end

  defp catalog_points(org, mission_id) do
    case Application.get_env(:cadence, :derived_point_catalog) do
      nil -> MapSet.new()
      catalog -> org |> catalog.list_points(mission_id) |> MapSet.new(& &1.point_id)
    end
  end

  # Today's direct-save rule: numbers, red_low <= yellow_low < yellow_high <= red_high.
  defp threshold_errors(thresholds) when is_map(thresholds) do
    cond do
      Map.keys(thresholds) -- @thresholds != [] ->
        [F.error("thresholds", "Use red_low, yellow_low, yellow_high and red_high")]

      Enum.any?(thresholds, fn {_key, value} -> not is_number(value) end) ->
        [F.error("thresholds", "Thresholds are numbers")]

      not ordered?(thresholds) ->
        [F.error("thresholds", "Order the limits: red low ≤ yellow low < yellow high ≤ red high")]

      true ->
        []
    end
  end

  defp threshold_errors(_thresholds), do: [F.error("thresholds", "Enter the limits")]

  defp ordered?(thresholds) do
    present = for key <- @thresholds, Map.has_key?(thresholds, key), do: {key, thresholds[key]}

    present
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn
      [{"yellow_low", low}, {"yellow_high", high}] -> low < high
      [{_a, low}, {_b, high}] -> low <= high
    end)
  end

  defp definition(document),
    do:
      Definition.new(%{
        mission_id: "",
        point_id: document["point_id"],
        limit_set_name: document["limit_set_name"] || "DEFAULT",
        thresholds: document["thresholds"] || %{},
        metadata: document["metadata"] || %{}
      })

  defp document(%Definition{} = definition),
    do: %{
      "point_id" => definition.point_id,
      "limit_set_name" => definition.limit_set_name,
      "thresholds" => definition.thresholds || %{},
      "metadata" => definition.metadata || %{}
    }

  defp label(document), do: "#{document["point_id"]} (#{document["limit_set_name"]})"
end
