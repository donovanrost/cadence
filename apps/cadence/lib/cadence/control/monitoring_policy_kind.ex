defmodule Cadence.Control.MonitoringPolicyKind do
  @moduledoc """
  Change-set kind for a mission's limits and alarm rules (ADR-020 P3 slice M2, #451; ux U108), in
  the **monitoring** lane.

  One entity per monitoring policy, by its declaration's semantic id: a mission policy's (created
  here, under `/mission/monitoring`) or a catalog policy's (editing it stages an explicit replace).
  The document is the policy as the console edits it (the agreed shape on #451):
  `{name, parameter_id, policy_kind: limit | alarm_rule, default_rules, contexts?, minimum_violations?,
  minimum_conformance?, missing_state?, invalid_state?, disabled?, spacecraft_ids?, overrides?,
  compositions?, description?}`. A `limit` is range rules only.

  `write/7` changes nothing per op: the apply's generation builds the next authored layer from the
  set's entries (`Control.MonitoringGeneration`). `holds/3` runs the compile every composition in
  use would run with that layer, in memory, so a dangling reference, a drifted catalog policy or a
  bad override is a NO-GO on the preview, not a failed apply.
  """

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.Control.MonitoringGeneration
  alias Cadence.MissionModels.{AuthoredLayer, Compositions, DeclarationProjection, Selection}
  alias Cadence.Platform.ConfigFields, as: F

  @fields ~w(name parameter parameter_id policy_kind default_rules contexts minimum_violations
    minimum_conformance missing_state invalid_state disabled spacecraft_ids overrides compositions
    description)
  @rule_kinds ~w(range comparison enumerated boolean string)
  @severities ~w(watch warning distress critical severe)
  @states ~w(unknown normal watch warning distress critical severe)

  @impl true
  def kind, do: "monitoring_policy"

  @impl true
  def id_prefix, do: "monitoring_policy"

  @impl true
  def lane, do: :monitoring

  @impl true
  def create_entity_id(%{"name" => name}) when is_binary(name), do: AuthoredLayer.entity_id(name)

  @impl true
  def load(organization_id, mission_id, ids) do
    authored =
      organization_id
      |> AuthoredLayer.current(mission_id)
      |> Map.take(ids)
      |> Map.new(fn {id, declaration} -> {id, document(declaration_map(declaration))} end)

    missing = ids -- Map.keys(authored)
    Map.merge(catalog_documents(organization_id, mission_id, missing), authored)
  end

  @impl true
  def normalize(:delete, _id, nil), do: {:ok, nil}

  def normalize(_action, _id, %{} = document) do
    errors =
      F.only(document, @fields) ++
        F.text(document, "name", 1..120, required: true, label: "Name") ++
        F.one_of(document, "policy_kind", ~w(limit alarm_rule), required: true) ++
        parameter_errors(document) ++
        rules_errors(document) ++
        count_errors(document, "minimum_violations") ++
        count_errors(document, "minimum_conformance") ++
        F.one_of(document, "missing_state", @states) ++
        F.one_of(document, "invalid_state", @states) ++
        ids_errors(document, "spacecraft_ids", 500) ++ ids_errors(document, "compositions", 32)

    F.result(document, errors)
  end

  def normalize(_action, _id, _document),
    do: {:error, [F.error("", "Enter the policy's name, point and rules")]}

  # Fill the parameter's path (what the authored declaration references) from its id.
  @impl true
  def translate(
        _organization_id,
        _mission_id,
        _previous,
        %{"parameter" => path} = proposed,
        _touched
      )
      when is_binary(path),
      do: {:ok, proposed}

  def translate(
        organization_id,
        mission_id,
        _previous,
        %{"parameter_id" => id} = proposed,
        _touched
      )
      when is_binary(id) do
    case parameter_path(organization_id, mission_id, id) do
      nil -> {:error, [F.error("parameter_id", "This point isn't in the mission's model")]}
      path -> {:ok, Map.put(proposed, "parameter", path)}
    end
  end

  def translate(_organization_id, _mission_id, _previous, proposed, _touched), do: {:ok, proposed}

  # A mission policy's id comes from its name, so a rename is a new policy (and the old one's retire).
  @impl true
  def validate(_organization_id, _mission_id, :update, _id, %{"name" => old}, %{"name" => new})
      when old != new,
      do:
        {:error,
         [F.error("name", "A policy can't be renamed; add a new one and retire this one")]}

  def validate(_organization_id, _mission_id, _action, _id, _previous, _proposed), do: :ok

  # The apply's generation builds the layer from the set's entries.
  @impl true
  def write(_organization_id, _mission_id, _action, _id, _previous, proposed, _options),
    do: {:ok, proposed, []}

  @impl true
  def summary(:create, nil, proposed), do: "Add #{noun(proposed)} #{proposed["name"]}"
  def summary(:delete, previous, nil), do: "Retire #{noun(previous)} #{previous["name"]}"

  def summary(:update, %{"source" => "catalog"} = previous, _proposed),
    do: "Replace catalog limits for #{previous["name"]}"

  def summary(:update, previous, _proposed), do: "Edit #{noun(previous)} #{previous["name"]}"

  @impl true
  def runtime_impact(_action, _previous, _proposed), do: :none

  @doc """
  NO-GOs before anything applies: the candidate authored layer compiled with every composition in
  use, in memory. One hold per (composition, cause), naming the composition and the definitions.
  """
  @impl true
  def holds(organization_id, mission_id, entries) do
    monitoring = Enum.filter(entries, &(&1.kind in ["monitoring_policy", "derived_parameter"]))

    if monitoring == [],
      do: [],
      else: check(organization_id, mission_id, monitoring)
  end

  defp check(organization_id, mission_id, entries) do
    compositions = in_use(organization_id, mission_id)

    case AuthoredLayer.build(organization_id, mission_id, entries, compositions, "preview") do
      {:ok, layer} ->
        Enum.flat_map(compositions, &composition_holds(organization_id, mission_id, &1, layer))

      {:error, reason} ->
        [hold(reason, %{reason: inspect(reason)}, "Not staged: #{sentence(reason)}")]
    end
  end

  defp composition_holds(organization_id, mission_id, composition_id, layer) do
    case Compositions.check_at(organization_id, mission_id, composition_id, layer) do
      {:ok, []} ->
        []

      {:ok, diagnostics} ->
        diagnostics
        |> Enum.group_by(& &1.code)
        |> Enum.map(fn {code, found} ->
          hold(
            :monitoring_compile_no_go,
            %{
              composition_id: composition_id,
              code: String.downcase(code),
              definitions: Enum.map(found, & &1.semantic_id)
            },
            "#{length(found)} monitoring definition(s) don't compile in this composition (#{code})."
          )
        end)

      {:error, reason} ->
        [hold(:monitoring_compile_no_go, %{composition_id: composition_id}, inspect(reason))]
    end
  end

  defp hold(reason, details, sentence) do
    %{
      op_id: nil,
      change_id: nil,
      kind: kind(),
      entity_id: nil,
      reason: reason,
      blocking: true,
      sentence: sentence,
      details: details
    }
  end

  defp sentence(:monitoring_set_changes_nothing), do: "these changes change nothing."

  defp sentence({:monitoring_catalog_policy_delete, _}),
    do: "a catalog policy can't be deleted; turn it off instead."

  defp sentence({:monitoring_catalog_policy_differs, _}),
    do: "the catalogs in use differ on this policy."

  defp sentence({:monitoring_layer_too_large, max}),
    do: "a mission can't have more than #{max} monitoring definitions."

  defp sentence(reason), do: inspect(reason)

  ## Reads

  defp in_use(organization_id, mission_id),
    do: MonitoringGeneration.compositions_in_use(organization_id, mission_id)

  defp bases(organization_id, mission_id) do
    for composition_id <- in_use(organization_id, mission_id),
        {:ok, revision_id} <- [Selection.select(organization_id, mission_id, composition_id)],
        uniq: true,
        do: revision_id
  end

  defp catalog_documents(_organization_id, _mission_id, []), do: %{}

  defp catalog_documents(organization_id, mission_id, ids) do
    organization_id
    |> bases(mission_id)
    |> Enum.reduce(%{}, fn revision_id, acc ->
      Map.merge(
        catalog_documents_in(organization_id, mission_id, revision_id, ids -- Map.keys(acc)),
        acc
      )
    end)
  end

  defp catalog_documents_in(_organization_id, _mission_id, _revision_id, []), do: %{}

  defp catalog_documents_in(organization_id, mission_id, revision_id, ids) do
    case DeclarationProjection.load(organization_id, mission_id, revision_id, ids) do
      {:ok, found} ->
        for {id, %{"kind" => "monitoring_policy"} = declaration} <- found, into: %{} do
          {id, declaration |> document() |> Map.put("source", "catalog")}
        end

      {:error, _unavailable} ->
        %{}
    end
  end

  defp parameter_path(organization_id, mission_id, id) do
    organization_id
    |> bases(mission_id)
    |> Enum.find_value(fn revision_id ->
      case DeclarationProjection.load(organization_id, mission_id, revision_id, [id]) do
        {:ok, %{^id => %{"kind" => "parameter", "qualified_name" => path}}} -> path
        _other -> nil
      end
    end)
  end

  # A stored or authored declaration as the kind's document.
  defp document(%{} = declaration) do
    definition = declaration["definition"] || %{}
    parameter = Enum.find(declaration["references"] || [], &(&1["role"] == "parameter")) || %{}

    definition
    |> Map.take(@fields)
    |> Map.merge(%{
      "name" => declaration["qualified_name"] |> to_string() |> String.split("/") |> List.last(),
      "parameter" => parameter["resolved_qualified_name"] || parameter["source_ref"],
      "parameter_id" => parameter["resolved_id"],
      "policy_kind" => definition["policy_kind"] || policy_kind(definition)
    })
  end

  defp declaration_map(declaration) do
    %{
      "kind" => "monitoring_policy",
      "qualified_name" => declaration.qualified_name,
      "definition" => Map.new(declaration.definition, fn {k, v} -> {to_string(k), v} end),
      "references" =>
        Enum.map(declaration.references, fn reference ->
          %{
            "role" => to_string(reference.role),
            "source_ref" => reference.source_ref,
            "resolved_id" => reference.resolved_id,
            "resolved_qualified_name" => reference.resolved_qualified_name
          }
        end)
    }
  end

  # A catalog policy is a limit when it is range rules only.
  defp policy_kind(definition) do
    rules = List.wrap(definition["default_rules"])

    if rules != [] and Enum.all?(rules, &(to_string(&1["kind"]) == "range")),
      do: "limit",
      else: "alarm_rule"
  end

  defp noun(%{"policy_kind" => "alarm_rule"}), do: "alarm rule"
  defp noun(_limits), do: "limits"

  ## Field checks

  defp parameter_errors(document) do
    if is_binary(document["parameter_id"]) or is_binary(document["parameter"]),
      do: [],
      else: [F.error("parameter_id", "Choose the point these limits watch")]
  end

  defp rules_errors(%{"default_rules" => rules} = document) when is_list(rules) and rules != [] do
    rule_errors =
      rules
      |> Enum.with_index()
      |> Enum.flat_map(fn {rule, index} -> rule_errors(rule, "default_rules.#{index}") end)

    limit_errors =
      if document["policy_kind"] == "limit" and Enum.any?(rules, &(&1["kind"] != "range")),
        do: [F.error("default_rules", "Limits are ranges; use an alarm rule for anything else")],
        else: []

    rule_errors ++ limit_errors
  end

  defp rules_errors(_document), do: [F.error("default_rules", "Add at least one rule")]

  defp rule_errors(%{} = rule, path) do
    kind =
      if rule["kind"] in @rule_kinds,
        do: [],
        else: [F.error(path <> ".kind", "Choose a rule kind")]

    severity =
      if rule["severity"] in @severities,
        do: [],
        else: [F.error(path <> ".severity", "Choose a severity")]

    kind ++ severity
  end

  defp rule_errors(_rule, path), do: [F.error(path, "A rule is an object")]

  defp count_errors(document, key) do
    case document[key] do
      nil -> []
      n when is_integer(n) and n >= 1 and n <= 1_000 -> []
      _other -> [F.error(key, "A count from 1 to 1000")]
    end
  end

  defp ids_errors(document, key, max) do
    case document[key] do
      nil ->
        []

      ids when is_list(ids) and length(ids) <= max ->
        if Enum.all?(ids, &is_binary/1), do: [], else: [F.error(key, "A list of ids")]

      _other ->
        [F.error(key, "At most #{max} ids")]
    end
  end
end
