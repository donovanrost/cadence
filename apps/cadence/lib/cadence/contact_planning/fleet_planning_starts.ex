defmodule Cadence.ContactPlanning.FleetPlanningStarts do
  @moduledoc "Reviewed manual fleet creation: exact input claim and atomic database materialization."
  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.ContactPlanning.{
    ContactRequirementTemplates,
    FleetPlanningRuns,
    FleetStartInputs,
    FleetStartProjection
  }

  alias Cadence.Repo

  def preview(%Scope{} = scope, mission_id, params) do
    with :ok <- authorize(scope, mission_id),
         {:ok, window, pages, _} <- admit(params, :preview),
         {:ok, inputs} <- FleetStartInputs.load(scope, mission_id, window) do
      {:ok, FleetStartProjection.review(inputs, pages)}
    end
  end

  def create(%Scope{} = scope, mission_id, params) do
    with :ok <- authorize(scope, mission_id),
         {:ok, window, _, evidence} <- admit(params, :create) do
      Repo.transaction(fn -> claim(scope, mission_id, window, evidence) end)
      |> case do
        {:ok, {run, refs}} -> {:ok, run, refs}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp claim(scope, mission_id, window, evidence) do
    with {:ok, inputs} <- FleetStartInputs.load(scope, mission_id, window, true),
         true <- inputs.evidence === evidence,
         {:ok, generated, materialization} <- materialize(scope, mission_id, inputs),
         refs <- requirement_refs(inputs, generated),
         {:ok, run, refs} <-
           FleetPlanningRuns.create(scope, mission_id, %{
             horizon_start: window.horizon_start,
             horizon_end: window.horizon_end,
             trigger_kind: :manual,
             requirement_refs: refs,
             creation_review_document: evidence,
             template_materialization_document: materialization
           }) do
      {run, refs}
    else
      false -> Repo.rollback(:fleet_planning_review_changed)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def validate_input(params, mode) do
    case admit(params, mode) do
      {:ok, _, _, _} -> :ok
      {:error, _} = error -> error
    end
  end

  def admit(params, mode) when is_map(params) and mode in [:preview, :create] do
    params = Map.delete(params, "mission_id")

    allowed =
      if mode == :preview,
        do: ~w(fleet_run requirements_page templates_page),
        else: ~w(fleet_run evidence)

    with true <- Enum.all?(Map.keys(params), &(&1 in allowed)),
         form when is_map(form) <- params["fleet_run"],
         true <- Enum.sort(Map.keys(form)) == ~w(horizon_end horizon_start include_recurring),
         {:ok, starts, 0} <- datetime(form["horizon_start"]),
         {:ok, ends, 0} <- datetime(form["horizon_end"]),
         true <- is_boolean(form["include_recurring"]),
         true <- DateTime.before?(starts, ends),
         {:ok, pages} <- pages(params),
         :ok <- evidence_shape(params["evidence"], mode) do
      {:ok,
       %{horizon_start: starts, horizon_end: ends, include_recurring: form["include_recurring"]},
       pages, params["evidence"]}
    else
      _ -> {:error, :fleet_planning_start_input_invalid}
    end
  end

  def admit(_, _), do: {:error, :fleet_planning_start_input_invalid}

  defp datetime(value) when is_binary(value) and byte_size(value) <= 40,
    do: DateTime.from_iso8601(value)

  defp datetime(_), do: {:error, :invalid_datetime}

  defp pages(params) do
    values = Enum.map(~w(requirements_page templates_page), &Map.get(params, &1, 1))

    if Enum.all?(values, &(is_integer(&1) and &1 in 1..1_000_000)),
      do: {:ok, Enum.zip(~w(requirements_page templates_page), values) |> Map.new()},
      else: {:error, :invalid_page}
  end

  defp evidence_shape(nil, :preview), do: :ok

  defp evidence_shape(e, :create) when is_map(e) do
    keys =
      ~w(contract_version organization_id mission_id policy_id policy_version policy_sha256 input_sha256)

    if Enum.sort(Map.keys(e)) == Enum.sort(keys) and e["contract_version"] === 1 and
         is_integer(e["policy_version"]) and e["policy_version"] > 0 and
         Enum.all?(
           ~w(organization_id mission_id policy_id),
           &(is_binary(e[&1]) and byte_size(e[&1]) in 1..240)
         ) and
         Enum.all?(
           ~w(policy_sha256 input_sha256),
           &(is_binary(e[&1]) and Regex.match?(~r/\A[a-f0-9]{64}\z/, e[&1]))
         ), do: :ok, else: {:error, :invalid_review}
  end

  defp evidence_shape(_, _), do: {:error, :invalid_review}

  defp authorize(scope, mission),
    do:
      Policy.authorize(scope, :operate_mission, %{
        organization_id: scope.organization_id,
        mission_id: mission
      })

  # These calls intentionally stay in the claiming process and its transaction.
  # materialize_active uses worker connections and cannot provide atomic rollback here.
  defp materialize(scope, mission, inputs) do
    inputs.templates
    |> Enum.reduce_while({:ok, []}, fn t, {:ok, results} ->
      case ContactRequirementTemplates.materialize(
             scope,
             mission,
             t.template.contact_requirement_template_id,
             inputs.window.horizon_start,
             inputs.window.horizon_end
           ) do
        {:ok, rows} ->
          append_reviewed_materialization(t, rows, results)

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results} ->
        {:ok, results,
         %{
           "template_count" => length(inputs.templates),
           "occurrence_count" => length(results),
           "created_count" => Enum.count(results, &(&1.status == :created)),
           "existing_count" => Enum.count(results, &(&1.status == :existing)),
           "skipped" => not inputs.window.include_recurring
         }}

      {:error, _} = error ->
        error
    end
  end

  defp append_reviewed_materialization(template, rows, results) do
    if reviewed_materialization?(template, rows),
      do: {:cont, {:ok, results ++ rows}},
      else: {:halt, {:error, :fleet_planning_review_changed}}
  end

  defp reviewed_materialization?(template, rows) do
    existing = Map.new(template.existing_occurrences, &{&1.at, &1})

    Enum.all?(rows, fn result ->
      occurrence = result.occurrence
      at = DateTime.to_unix(occurrence.occurrence_at, :microsecond)

      case {result.status, Map.get(existing, at)} do
        {:created, nil} ->
          true

        {:existing, %{state: "generated", requirement_id: id, requirement_version: version}} ->
          occurrence.generated_contact_requirement_id == id and
            occurrence.generated_contact_requirement_version == version

        _ ->
          false
      end
    end)
  end

  defp requirement_refs(inputs, generated) do
    existing = Enum.map(inputs.requirements, fn {_, v} -> reference(v) end)
    reviewed_ids = MapSet.new(existing, & &1.contact_requirement_id)

    additional =
      generated
      |> Enum.filter(&(&1.status == :created))
      |> Enum.reject(&MapSet.member?(reviewed_ids, &1.requirement.contact_requirement_id))
      |> Enum.filter(fn result ->
        v = result.requirement_version

        result.requirement.lifecycle_state == :active and
          DateTime.before?(v.earliest_start, inputs.window.horizon_end) and
          DateTime.after?(v.latest_end, inputs.window.horizon_start)
      end)
      |> Enum.map(&reference(&1.requirement_version))

    Enum.uniq_by(existing ++ additional, & &1.contact_requirement_id)
  end

  defp reference(version),
    do: %{contact_requirement_id: version.contact_requirement_id, version: version.version}
end
