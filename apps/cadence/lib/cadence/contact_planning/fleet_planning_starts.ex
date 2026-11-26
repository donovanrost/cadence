defmodule Cadence.ContactPlanning.FleetPlanningStarts do
  @moduledoc "Reviewed manual fleet creation: exact input claim and batched atomic materialization."
  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.ContactPlanning.{
    FleetPlanningRuns,
    FleetStartInputs,
    FleetStartMaterialization,
    FleetStartProjection,
    TemplateSupersession
  }

  alias Cadence.Repo

  @doc """
  The start's template fan-out over `window` (`%{horizon_start, horizon_end}`): `count` toward
  the fan-out limit, `limit`, and the templates whose per-run cap cuts the window short
  (FleetStartInputs.estimate/4). Reads no requirement or occurrence rows (U52).
  """
  def estimate(%Scope{} = scope, mission_id, window) do
    with :ok <- authorize(scope, mission_id),
         do: FleetStartInputs.estimate(scope.organization_id, mission_id, window)
  end

  def preview(%Scope{} = scope, mission_id, params) do
    with :ok <- authorize(scope, mission_id),
         {:ok, window, pages, _} <- admit(params, :preview),
         {:ok, as_of} <- preview_as_of(params["as_of"]),
         {:ok, inputs} <- FleetStartInputs.load(scope, mission_id, window, false, as_of) do
      {:ok, FleetStartProjection.review(inputs, pages)}
    end
  end

  @doc """
  Creates the reviewed run. `operation_id:` (optional) records the console
  operation on the run inside the same transaction, so a replay always finds it.
  """
  def create(%Scope{} = scope, mission_id, params, opts \\ []) do
    with :ok <- authorize(scope, mission_id),
         {:ok, window, _, evidence} <- admit(params, :create) do
      Repo.transaction(
        fn ->
          claim(
            scope,
            mission_id,
            window,
            evidence,
            Keyword.get(opts, :operation_id),
            Keyword.get(opts, :occupied, [])
          )
        end,
        timeout: :infinity
      )
      |> case do
        {:ok, {run, refs}} -> {:ok, run, refs}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # A review older than this is stale: its `as_of` no longer says what "future" means.
  @review_max_age_s 15 * 60

  defp claim(scope, mission_id, window, evidence, operation_id, occupied) do
    with {:ok, as_of} <- review_as_of(evidence),
         {:ok, inputs} <- FleetStartInputs.load(scope, mission_id, window, true, as_of),
         true <- inputs.evidence === evidence,
         candidates <- supersession_candidates(scope, mission_id, inputs),
         :ok <- prefer_index_scans_for_materialization(),
         {:ok, generated, materialization} <- materialize(scope, mission_id, inputs),
         :ok <- TemplateSupersession.cancel_prepared(scope, mission_id, candidates, as_of),
         requirements <- requirement_pairs(inputs, generated),
         {:ok, run, refs} <-
           FleetPlanningRuns.create_reviewed(
             scope,
             mission_id,
             %{
               horizon_start: window.horizon_start,
               horizon_end: window.horizon_end,
               trigger_kind: :manual,
               creation_review_document: evidence,
               template_materialization_document: materialization,
               occupied_document: occupied
             },
             requirements
           ),
         :ok <- record_operation(scope, mission_id, run, operation_id) do
      {run, refs}
    else
      false -> Repo.rollback(:fleet_planning_review_changed)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp prefer_index_scans_for_materialization do
    # PostgreSQL caches RI trigger plans per backend. A new fleet can create its parent rows
    # inside this transaction before table statistics see them; a broad or sequential FK plan
    # then revisits prior inserts for each child. The exact-key indexes and this transaction-
    # local setting keep both cold and previously used backends on indexed lookups.
    Repo.query!("SET LOCAL enable_seqscan = off")
    :ok
  end

  defp record_operation(_scope, _mission_id, _run, nil), do: :ok

  defp record_operation(scope, mission_id, run, operation_id),
    do:
      FleetPlanningRuns.claim_operation(
        scope.organization_id,
        mission_id,
        run.fleet_planning_run_id,
        operation_id
      )

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
        do: ~w(fleet_run requirements_page templates_page as_of),
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

  # Later review pages pass the first page's `evidence.as_of`, so every page is one review.
  defp preview_as_of(nil), do: {:ok, nil}
  defp preview_as_of(value), do: review_as_of(%{"as_of" => value})

  defp review_as_of(evidence) do
    with value when is_binary(value) <- evidence["as_of"],
         {:ok, as_of, _offset} <- DateTime.from_iso8601(value),
         age = DateTime.diff(DateTime.utc_now(), as_of),
         true <- age >= -60 and age <= @review_max_age_s do
      {:ok, as_of}
    else
      _stale -> {:error, :fleet_planning_review_changed}
    end
  end

  defp evidence_shape(nil, :preview), do: :ok

  defp evidence_shape(e, :create) when is_map(e) do
    keys =
      ~w(contract_version organization_id mission_id policy_id policy_version policy_sha256 input_sha256 as_of)

    if Enum.sort(Map.keys(e)) == Enum.sort(keys) and e["contract_version"] === 1 and
         is_integer(e["policy_version"]) and e["policy_version"] > 0 and
         evidence_values?(e),
       do: :ok,
       else: {:error, :invalid_review}
  end

  defp evidence_shape(_, _), do: {:error, :invalid_review}

  defp evidence_values?(e) do
    Enum.all?(
      ~w(organization_id mission_id policy_id),
      &(is_binary(e[&1]) and byte_size(e[&1]) in 1..240)
    ) and
      Enum.all?(
        ~w(policy_sha256 input_sha256),
        &(is_binary(e[&1]) and Regex.match?(~r/\A[a-f0-9]{64}\z/, e[&1]))
      ) and match?({:ok, _, _}, DateTime.from_iso8601(to_string(e["as_of"])))
  end

  defp authorize(scope, mission),
    do:
      Policy.authorize(scope, :operate_mission, %{
        organization_id: scope.organization_id,
        mission_id: mission
      })

  # Batch inserts stay on the claiming connection. Review drift still rolls back the entire
  # claim, including generated requirements, occurrences, refs, and the run.
  defp materialize(scope, mission, inputs) do
    inputs.templates
    |> Enum.reduce_while({:ok, [], 0}, fn t, {:ok, batches, count} ->
      case FleetStartMaterialization.materialize(scope, mission, t) do
        {:ok, pairs, occurrence_count} ->
          {:cont, {:ok, [pairs | batches], count + occurrence_count}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, batches, occurrence_count} ->
        pairs = batches |> Enum.reverse() |> List.flatten()
        created_count = length(pairs)

        {:ok, pairs,
         %{
           "template_count" => length(inputs.templates),
           "occurrence_count" => occurrence_count,
           "created_count" => created_count,
           "existing_count" => occurrence_count - created_count,
           "skipped" => not inputs.window.include_recurring
         }}

      {:error, _} = error ->
        error
    end
  end

  # Read the older rows before the write batches while the table statistics still reflect
  # its contents. Freshly generated requirements are already on the reviewed template version.
  defp supersession_candidates(scope, mission_id, inputs) do
    templates =
      Enum.filter(inputs.templates, fn t ->
        t.version.version > 1 or t.version.target_document["kind"] != "spacecraft_ids"
      end)

    TemplateSupersession.prepare(scope.organization_id, mission_id, templates, inputs.as_of)
  end

  defp requirement_pairs(inputs, generated) do
    existing = inputs.requirements
    reviewed_ids = MapSet.new(existing, fn {r, _v} -> r.contact_requirement_id end)

    additional =
      generated
      |> Enum.reject(fn {r, _v} -> MapSet.member?(reviewed_ids, r.contact_requirement_id) end)
      |> Enum.filter(fn {r, v} ->
        r.lifecycle_state == :active and
          DateTime.before?(v.earliest_start, inputs.window.horizon_end) and
          DateTime.after?(v.latest_end, inputs.window.horizon_start)
      end)

    Enum.uniq_by(existing ++ additional, fn {r, _v} -> r.contact_requirement_id end)
  end
end
