defmodule Cadence.Governance.DerivedTelemetryKind do
  @moduledoc """
  Change-set kind for derived telemetry points (DECISIONS #77, stage 1).

  One entity per derived point (id = its derived definition id). The document is
  `{point_id, point_name, expression, metadata}`; source points come from the expression. Create
  writes version 1, update appends the next version, and delete **retires** the point: a final
  version marked retired, so its history stays and evaluation stops reading it.

  The point id is fixed once created, and can't reuse a catalog point's id or any derived point's
  (live or retired). Every source point the expression reads must be a catalog point of the
  mission's active binding set or a live derived point. Retiring a point another live definition
  still reads is a blocking HOLD (`derived_point_in_use`, ux U42), unless that one is retired or
  changed to stop reading it in the same change set.

  Each evaluation run reads the live definitions when it starts, so applying needs no runtime
  notification (`runtime_impact` none). The ops-console direct save stays until the user decides
  (#77 decisions 1 and 2); both write the same versions.
  """

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.DerivedTelemetry.{Definition, ExpressionParser}
  alias Cadence.Governance
  alias Cadence.Platform.ConfigFields, as: F
  alias Cadence.Platform.SaveTrail

  @fields ~w(point_id point_name expression metadata)

  @impl true
  def kind, do: "derived_telemetry"

  @impl true
  def id_prefix, do: "derived_definition"

  @impl true
  def load(organization_id, mission_id, ids) do
    organization_id
    |> Governance.list_derived_definitions(mission_id)
    |> Enum.filter(&(&1.derived_definition_id in ids))
    |> Map.new(&{&1.derived_definition_id, document(&1)})
  end

  @impl true
  def normalize(:delete, _id, nil), do: {:ok, nil}

  def normalize(_action, _id, %{} = document) do
    document =
      document
      |> Map.put_new("metadata", %{})
      |> Map.update("point_name", nil, &blank_nil/1)

    errors =
      F.only(document, @fields) ++
        F.text(document, "point_id", 1..240, required: true, label: "Point ID") ++
        F.text(document, "point_name", 1..240, label: "Name") ++
        F.text(document, "expression", 1..8192, required: true, label: "Expression") ++
        F.map(document, "metadata") ++ expression_errors(document)

    F.result(document, errors)
  end

  def normalize(_action, _id, _document),
    do: {:error, [F.error("", "Enter the derived point's id and expression")]}

  @impl true
  def validate(_organization_id, _mission_id, :delete, _id, _previous, nil), do: :ok

  def validate(org, mission_id, action, _id, previous, proposed) do
    catalog = catalog_points(org, mission_id)
    live = Governance.list_derived_definitions(org, mission_id)

    errors =
      point_id_errors(org, mission_id, action, previous, proposed, catalog) ++
        source_errors(proposed, catalog, live)

    if errors == [], do: :ok, else: {:error, errors}
  end

  @impl true
  def write(_organization_id, mission_id, :create, id, nil, proposed, _options) do
    %{
      derived_definition_id: id,
      mission_id: mission_id,
      point_id: proposed["point_id"],
      point_name: proposed["point_name"] || proposed["point_id"],
      expression: proposed["expression"],
      version: 1,
      metadata: SaveTrail.change_set(proposed["metadata"])
    }
    |> Definition.new()
    |> Governance.persist_derived_definition()
    |> stored()
  end

  def write(organization_id, mission_id, :update, id, _previous, proposed, _options) do
    with {:ok, current} <-
           Governance.fetch_derived_definition(organization_id, mission_id, id, nil) do
      organization_id
      |> Governance.append_derived_definition(
        mission_id,
        %{
          point_id: current.point_id,
          point_name: proposed["point_name"] || current.point_id,
          expression: proposed["expression"],
          expected_definition_id: id,
          metadata: SaveTrail.change_set(proposed["metadata"])
        },
        current.version
      )
      |> stored()
    end
  end

  def write(organization_id, mission_id, :delete, id, _previous, nil, options) do
    actor = Map.get(options || %{}, :actor) || %{}

    case Governance.retire_derived_definition(organization_id, mission_id, id, actor["id"]) do
      {:ok, _retired} -> {:ok, nil, []}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def summary(:create, nil, proposed), do: "Add derived point #{label(proposed)}"
  def summary(:delete, previous, nil), do: "Retire derived point #{label(previous)}"
  def summary(:update, previous, _proposed), do: "Edit derived point #{label(previous)}"

  @impl true
  def runtime_impact(_action, _previous, _proposed), do: :none

  @doc """
  Blocking HOLDs (ux U42): a retired point that another live definition still reads after the
  change set (one not retired here, and not changed here to stop reading it).
  """
  @impl true
  def holds(organization_id, mission_id, entries) do
    retired =
      for %{kind: "derived_telemetry", op: :delete, previous: %{"point_id" => point}} = entry <-
            entries,
          into: %{},
          do: {point, entry}

    if retired == %{},
      do: [],
      # Definitions as they stand after the change set (the run's writes are already applied).
      else:
        in_use_holds(retired, Governance.list_derived_definitions(organization_id, mission_id))
  end

  defp in_use_holds(retired, live) do
    Enum.flat_map(retired, fn {point, entry} ->
      case Enum.filter(live, &(point in &1.source_point_ids)) do
        [] -> []
        users -> [in_use(entry, point, users)]
      end
    end)
  end

  defp in_use(entry, point, users) do
    used_by =
      Enum.map(
        users,
        &%{point_id: &1.point_id, name: &1.point_name, definition_id: &1.derived_definition_id}
      )

    %{
      op_id: nil,
      change_id: nil,
      kind: kind(),
      entity_id: entry.entity_id,
      reason: :derived_point_in_use,
      blocking: true,
      sentence: in_use_sentence(point, used_by),
      details: %{point_id: point, used_by: used_by}
    }
  end

  # ux U42 (decisions.md).
  defp in_use_sentence(point, [%{point_id: user}]),
    do:
      "#{point} can't be retired: #{user}'s expression uses it. " <>
        "Change or retire #{user} in this change set too."

  defp in_use_sentence(point, used_by) do
    names = used_by |> Enum.map(& &1.point_id)
    shown = Enum.take(names, 5)
    more = length(names) - length(shown)

    list =
      Enum.join(shown, ", ") <> if(more > 0, do: " and #{more} more", else: "")

    "#{point} can't be retired: #{length(names)} derived points use it in their expressions " <>
      "(#{list}). Change or retire them in this change set too."
  end

  defp point_id_errors(_org, _mission, :update, previous, proposed, _catalog) do
    if previous["point_id"] == proposed["point_id"],
      do: [],
      else: [
        F.error("point_id", "A derived point's id can't change; retire it and add a new one")
      ]
  end

  defp point_id_errors(org, mission, :create, _previous, proposed, catalog) do
    point = proposed["point_id"]

    cond do
      MapSet.member?(catalog, point) ->
        [F.error("point_id", "A catalog point already has this id")]

      Governance.derived_point_used?(org, mission, point) ->
        [
          F.error(
            "point_id",
            "A derived point already uses this id, or did before it was retired"
          )
        ]

      true ->
        []
    end
  end

  defp source_errors(proposed, catalog, live) do
    derived = MapSet.new(live, & &1.point_id)
    sources = sources(proposed["expression"])

    case Enum.reject(sources, &(MapSet.member?(catalog, &1) or MapSet.member?(derived, &1))) do
      [] -> []
      [unknown | _] -> [F.error("expression", "Unknown point #{unknown}")]
    end
  end

  # The mission's catalog points, through the :derived_point_catalog adapter
  # (Cadence.Ops.PointCatalog), so governance keeps no compile-time edge to projections.
  defp catalog_points(org, mission_id) do
    case Application.get_env(:cadence, :derived_point_catalog) do
      nil -> MapSet.new()
      catalog -> org |> catalog.list_points(mission_id) |> MapSet.new(& &1.point_id)
    end
  end

  defp expression_errors(%{"expression" => expression, "point_id" => point})
       when is_binary(expression) and expression != "" and is_binary(point) do
    definition =
      Definition.new(%{mission_id: "validation", point_id: point, expression: expression})

    case Definition.validate(definition) do
      :ok ->
        []

      {:error, :stateful_functions_not_supported} ->
        [F.error("expression", "Use a stateless expression")]

      {:error, reason} ->
        [F.error("expression", "The expression doesn't parse: #{describe(reason)}")]
    end
  end

  defp expression_errors(_document), do: []

  defp sources(expression) when is_binary(expression) do
    case ExpressionParser.extract_variables(expression) do
      {:ok, points} -> points
      {:error, _reason} -> []
    end
  end

  defp sources(_expression), do: []

  defp describe({:parse_error, message, rest, _line, _column}) when is_binary(rest),
    do: "#{message} near \"#{String.slice(rest, 0, 20)}\""

  defp describe({:unqualified_variable, name}),
    do: "#{name} isn't a point id; use PACKET.field or another derived point's id"

  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)

  defp stored({:ok, %Definition{} = definition}), do: {:ok, document(definition), []}
  defp stored({:error, reason}), do: {:error, reason}

  # Without the save trail: who saved the live version, and how, isn't a change to review.
  defp document(%Definition{} = definition),
    do: %{
      "point_id" => definition.point_id,
      "point_name" => definition.point_name,
      "expression" => definition.expression,
      "metadata" => SaveTrail.without(definition.metadata)
    }

  defp label(document), do: document["point_name"] || document["point_id"]

  defp blank_nil(value) when value in [nil, ""], do: nil
  defp blank_nil(value), do: value
end
