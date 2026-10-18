defmodule Cadence.Reads.ApplicationSurfaces.DataOperations.HistoricalWorkflows do
  @moduledoc "Scoped historical-workflow evidence, independent display pages and complete internal reviews."

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Jobs
  alias Cadence.Missions
  alias Cadence.Reads.{DataSources, Telemetry}

  alias Cadence.Telemetry.DataManagement.{
    WorkflowCorrections,
    WorkflowEventEvidence,
    WorkflowEvents,
    WorkflowPolicy
  }

  alias Cadence.Telemetry.Storage.BackfillLifecycleGroup, as: Group

  @page_size 25
  @stages ~w(approved rejected started completed failed)
  @summary_keys ~w(state size progress requested approved started completed failed resolved_failed retry_resolved correction_requested correction_started correction_completed correction_superseded retryable_failed nonretryable_failed)a
  @query_keys ~w(group page audit_page jobs_page origins_page bindings_page binding_q)

  def admit_query(params) when is_map(params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in @query_keys)),
         {:ok, group} <- query_text(params, "group", 240),
         {:ok, search} <- query_text(params, "binding_q", 200),
         {:ok, pages} <- query_pages(params) do
      {:ok, Map.merge(pages, %{group: if(group == "", do: nil, else: group), binding_q: search})}
    else
      _ -> {:error, :invalid_historical_workflow_query}
    end
  end

  def admit_query(_), do: {:error, :invalid_historical_workflow_query}

  def initial_defaults do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      "workflow" => "backfill",
      "run_id" => "",
      "realm" => "",
      "data_source_id" => "",
      "source_binding_id" => "",
      "point_ids" => "",
      "source_from" => DateTime.to_iso8601(DateTime.add(now, -3600)),
      "source_to" => DateTime.to_iso8601(now),
      "reason" => "",
      "confirmed" => "false"
    }
  end

  def load(%Scope{} = scope, mission_id, mode, params, defaults \\ initial_defaults()) do
    with :ok <- authorize(scope, mission_id, mode),
         {:ok, _mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, query} <- admit_query(params),
         {:ok, selected} <- selected_review(scope, mission_id, query.group) do
      context = %{organization_id: scope.organization_id, mission_id: mission_id}

      admin? =
        Policy.authorize(scope, :manage_missions, %{organization_id: scope.organization_id}) ==
          :ok

      directory =
        Telemetry.list_backfill_lifecycle_groups(mission_id,
          organization_id: scope.organization_id,
          page: query.page,
          page_size: @page_size
        )

      groups = %{
        directory
        | entries: Enum.map(directory.entries, &directory_entry(scope, mission_id, &1, selected))
      }

      bindings = binding_choices(scope, mission_id)

      choices =
        bindings
        |> Enum.filter(&binding_matches?(&1, query.binding_q))
        |> page(query.bindings_page)

      model = %{
        contract_version: 1,
        context: context,
        mode: mode,
        query: query,
        permissions: %{request: true, manage: admin?},
        groups: groups,
        selected: selected && selected_model(selected, query, admin?),
        bindings: choices,
        defaults: defaults
      }

      {:ok, model, %{selected: selected, bindings: Map.new(bindings, &{&1.id, &1.evidence})}}
    end
  end

  def group_review(%Scope{} = scope, mission_id, group_id) do
    with :ok <- authorize(scope, mission_id, "reader"),
         {:ok, _mission} <- Missions.fetch_mission(scope.organization_id, mission_id),
         {:ok, events} <-
           Telemetry.fetch_backfill_lifecycle_group_events(mission_id, group_id,
             organization_id: scope.organization_id
           ) do
      jobs = jobs(events, mission_id)
      corrected = corrected_references(events, scope.organization_id, mission_id)

      summary =
        Group.summary(events, events, retry_ready_fun: &retry_ready?(&1, jobs, corrected))
        |> Map.take(@summary_keys)

      workflows = Enum.map(events, &workflow/1) |> Enum.uniq()

      kind =
        case workflows do
          [value] -> value
          _ -> "mixed"
        end

      revision = digest({scope.organization_id, mission_id, group_id, events, jobs, corrected})

      {:ok,
       %{
         id: group_id,
         events: events,
         jobs: jobs,
         corrected: corrected,
         workflow: kind,
         summary: summary,
         evidence: revision
       }}
    end
  end

  defp binding_choices(scope, mission_id) do
    sources =
      DataSources.list_data_sources(scope.organization_id, mission_id)
      |> Map.new(&{&1.data_source_id, &1})

    now = DateTime.utc_now()

    DataSources.list_data_bindings(scope.organization_id, mission_id)
    |> Enum.filter(fn binding ->
      source = sources[binding.data_source_id]

      source && source.status == :active && binding.status == :active &&
        binding.logical_source == :telemetry &&
        (is_nil(binding.active_from) or DateTime.compare(binding.active_from, now) != :gt) &&
        (is_nil(binding.active_to) or DateTime.compare(binding.active_to, now) == :gt)
    end)
    |> Enum.sort_by(& &1.binding_id)
    |> Enum.map(fn binding ->
      source = Map.fetch!(sources, binding.data_source_id)

      %{
        id: binding.binding_id,
        source_id: source.data_source_id,
        realm: to_string(binding.realm),
        version: binding.binding_version,
        evidence: digest({binding, source.current_event_id, source.status})
      }
    end)
  end

  defp authorize(scope, mission, mode) do
    with true <- mode in ["reader", "manage"],
         true <- scope.mission_id in [nil, mission],
         :ok <-
           Policy.authorize(scope, :operate_mission, %{
             organization_id: scope.organization_id,
             mission_id: mission
           }) do
      if mode == "manage",
        do: Policy.authorize(scope, :manage_missions, %{organization_id: scope.organization_id}),
        else: :ok
    else
      _ -> {:error, :forbidden}
    end
  end

  defp selected_review(_, _, nil), do: {:ok, nil}
  defp selected_review(scope, mission, id), do: group_review(scope, mission, id)

  defp directory_entry(scope, mission, entry, selected) do
    result =
      if selected && selected.id == entry.id,
        do: {:ok, selected},
        else: group_review(scope, mission, entry.id)

    case result do
      {:ok, review} ->
        %{
          id: entry.id,
          event_count: length(review.events),
          last_event_at: timestamp(List.last(review.events).occurred_at),
          workflow: review.workflow,
          summary: review.summary
        }

      {:error, _} ->
        %{
          id: entry.id,
          event_count: entry.event_count,
          last_event_at: timestamp(entry.occurred_at),
          workflow: "unavailable",
          summary: nil
        }
    end
  end

  defp selected_model(review, query, admin?) do
    %{
      id: review.id,
      workflow: review.workflow,
      evidence: review.evidence,
      summary: review.summary,
      audit:
        review.events
        |> Enum.reverse()
        |> page(query.audit_page)
        |> Map.update!(
          :entries,
          &Enum.map(&1, fn event -> audit_event(event, review, admin?) end)
        ),
      jobs: page(job_entries(review.jobs), query.jobs_page),
      origins: page(origins(review.events), query.origins_page),
      transitions: Enum.map(@stages, &transition(review, &1, admin?)),
      retry: %{
        eligible_count:
          if(admin?,
            do: Enum.count(review.events, &retry_ready?(&1, review.jobs, review.corrected)),
            else: 0
          )
      }
    }
  end

  defp transition(review, stage, admin?) do
    sources = Group.stage_sources(review.events, stage)

    count =
      Enum.count(sources, fn event ->
        job = review.jobs[event.backfill_run_id]
        context = job_context(job) |> Map.put(:stage, Group.payload_value(event, :stage))
        reference = Group.payload_value(event, :corrects_event_id)

        admin? and review.workflow in ["backfill", "import"] and job != :foreign and
          not MapSet.member?(review.corrected, reference) and
          WorkflowPolicy.stage_action_policy(context, stage).eligible? and
          correction_transition_available?(event, stage)
      end)

    %{stage: stage, eligible_count: count, blocked_count: length(sources) - count}
  end

  defp correction_transition_available?(event, stage) do
    if WorkflowEventEvidence.correction?(event) do
      with {:ok, kind} <- WorkflowEvents.normalize_workflow(workflow(event)),
           {:ok, stage} <- WorkflowEvents.normalize_stage(stage) do
        WorkflowCorrections.review_transition(kind, stage, event, event_scope(event)) == :ok
      else
        _ -> false
      end
    else
      true
    end
  end

  defp audit_event(event, review, admin?) do
    {reason, truncated?} = display_text(event.reason)
    job = review.jobs[event.backfill_run_id]
    recovery = WorkflowEventEvidence.recovery_action(event)

    correction? =
      event.event_type in [:backfill_failed, :import_failed] and admin? and job != :foreign and
        not MapSet.member?(review.corrected, event.backfill_lifecycle_event_id) and
        WorkflowPolicy.correction_request_action_policy(
          Map.merge(job_context(job), %{
            event_id: event.backfill_lifecycle_event_id,
            recovery_action: recovery
          })
        ).eligible? and correction_request_available?(event)

    %{
      id: event.backfill_lifecycle_event_id,
      run_id: event.backfill_run_id,
      event_type: to_string(event.event_type),
      stage: Group.payload_value(event, :stage),
      point_id: event.point_id,
      realm: to_string(event.realm),
      source_id: event.data_source_id,
      binding_id: event.binding_id,
      source_from: timestamp(event.source_from),
      source_to: timestamp(event.source_to),
      occurred_at: timestamp(event.occurred_at),
      actor_id: event.actor_id,
      operation_id: Group.payload_value(event, :host_operation_id),
      reason: reason,
      reason_truncated: truncated?,
      correction_available: correction?
    }
  end

  defp correction_request_available?(event) do
    match?(
      {:ok, _, _},
      WorkflowCorrections.review_request(workflow(event), event_scope(event), %{
        "original_event_id" => event.backfill_lifecycle_event_id
      })
    )
  end

  defp event_scope(event),
    do: %{organization_id: event.organization_id, mission_id: event.mission_id}

  defp jobs(events, mission) do
    events
    |> Enum.map(& &1.backfill_run_id)
    |> Enum.uniq()
    |> Map.new(fn run ->
      value =
        case Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, run) do
          {:ok, %{mission_id: ^mission} = job} ->
            Map.take(job, [:job_id, :run_id, :status, :attempt_count, :started_at, :completed_at])

          {:ok, _} ->
            :foreign

          {:error, _} ->
            nil
        end

      {run, value}
    end)
  end

  defp job_entries(jobs) do
    jobs
    |> Enum.flat_map(fn
      {_run, value} when is_map(value) ->
        [
          %{
            id: value.job_id,
            run_id: value.run_id,
            status: to_string(value.status),
            attempts: value.attempt_count,
            started_at: timestamp(value.started_at),
            completed_at: timestamp(value.completed_at)
          }
        ]

      _ ->
        []
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp job_context(job) when is_map(job),
    do: %{job_id: job.job_id, job_status: to_string(job.status)}

  defp job_context(_), do: %{}

  defp corrected_references(events, org, mission) do
    events
    |> Enum.flat_map(fn event ->
      own =
        if event.event_type in [:backfill_failed, :import_failed],
          do: event.backfill_lifecycle_event_id,
          else: nil

      [own, Group.payload_value(event, :corrects_event_id)]
    end)
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.filter(
      &Telemetry.backfill_lifecycle_event_corrected?(&1,
        organization_id: org,
        mission_id: mission
      )
    )
    |> MapSet.new()
  end

  defp retry_ready?(event, jobs, corrected) do
    job = jobs[event.backfill_run_id]

    event.event_type in [:backfill_failed, :import_failed] and is_map(job) and
      WorkflowEventEvidence.job_id(event) in [nil, "", job.job_id] and
      not MapSet.member?(corrected, event.backfill_lifecycle_event_id) and
      WorkflowPolicy.retry_job_action_policy(
        Map.merge(job_context(job), %{
          event_id: event.backfill_lifecycle_event_id,
          retryable: to_string(WorkflowEventEvidence.retryable?(event)),
          recovery_action: WorkflowEventEvidence.recovery_action(event)
        })
      ).eligible?
  end

  defp origins(events) do
    events
    |> Enum.flat_map(fn event ->
      dashboard = Group.payload_value(event, :dashboard_context)
      review = Group.payload_value(event, :comparison_review_origin)
      dashboard_origin(dashboard) ++ comparison_origin(review)
    end)
    |> Enum.uniq()
    |> Enum.sort_by(&{&1.kind, &1.id})
  end

  defp dashboard_origin(%{"dashboard_id" => id}) when is_binary(id) and id != "",
    do: [%{kind: "dashboard", id: id}]

  defp dashboard_origin(_), do: []

  defp comparison_origin(%{"request_event_id" => id}) when is_binary(id) and id != "",
    do: [%{kind: "comparison_review", id: id}]

  defp comparison_origin(_), do: []

  defp page(entries, number),
    do: %{
      entries: Enum.slice(entries, (number - 1) * @page_size, @page_size),
      page: number,
      page_size: @page_size,
      total: length(entries)
    }

  defp workflow(event), do: event |> WorkflowEventEvidence.workflow() |> to_string()

  defp binding_matches?(binding, query),
    do:
      String.contains?(
        String.downcase(binding.id <> " " <> binding.source_id <> " " <> binding.realm),
        String.downcase(query)
      )

  defp digest(value),
    do:
      :crypto.hash(:sha256, :erlang.term_to_binary(value, [:deterministic]))
      |> Base.encode16(case: :lower)

  defp timestamp(nil), do: nil
  defp timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp display_text(value) when is_atom(value), do: display_text(to_string(value))

  defp display_text(value) when is_binary(value) do
    cond do
      not String.valid?(value) -> {"Unavailable reason", true}
      byte_size(value) <= 4096 -> {value, false}
      true -> {valid_prefix(binary_part(value, 0, 4096)), true}
    end
  end

  defp display_text(_), do: {"", false}

  defp valid_prefix(value),
    do:
      if(String.valid?(value),
        do: value,
        else: valid_prefix(binary_part(value, 0, byte_size(value) - 1))
      )

  defp query_text(params, key, limit) do
    value = Map.get(params, key, "")

    if is_binary(value) and byte_size(value) <= limit and String.valid?(value),
      do: {:ok, value},
      else: :error
  end

  defp query_pages(params) do
    Enum.reduce_while(
      ~w(page audit_page jobs_page origins_page bindings_page)a,
      {:ok, %{}},
      fn key, {:ok, pages} ->
        value = Map.get(params, Atom.to_string(key), "1")

        case (is_binary(value) and Regex.match?(~r/\A[1-9][0-9]{0,6}\z/, value)) &&
               Integer.parse(value) do
          {page, ""} when page <= 1_000_000 -> {:cont, {:ok, Map.put(pages, key, page)}}
          _ -> {:halt, :error}
        end
      end
    )
  end
end
