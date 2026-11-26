defmodule Cadence.ContactPlanning.FleetSearch do
  @moduledoc false

  alias Cadence.Comms.StationAvailability
  alias Cadence.ContactPlanning.{FleetPlanningRuns, Planner}
  alias Cadence.Contacts.ProviderScheduling
  alias Cadence.Control.Providers.FleetOpportunitySearch
  alias Cadence.Management.Contacts.PlanningResults

  @batch_size 250

  def run(scope, run, refs, requirements, policy, opts) do
    {pending, checkpointed} = Enum.split_with(refs, &is_nil(&1.contact_planning_run_id))

    with {:ok, actor} <- Planner.fleet_actor(scope, run.mission_id),
         {:ok, summary} <- load_checkpoints(run, checkpointed, length(refs)) do
      search_pending(scope, run, pending, requirements, actor, policy, opts, summary)
    end
  end

  defp load_checkpoints(run, refs, total) do
    refs
    |> Stream.chunk_every(@batch_size)
    |> Enum.reduce_while({:ok, initial_summary(total)}, fn batch, {:ok, summary} ->
      ids = Enum.map(batch, & &1.contact_planning_run_id)
      previous = PlanningResults.fetch_runs(run.organization_id, run.mission_id, ids)

      case validate_checkpoints(batch, previous) do
        {:ok, runs} -> {:cont, {:ok, add_runs(summary, runs)}}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_checkpoints(refs, previous) do
    Enum.reduce_while(refs, {:ok, []}, fn ref, {:ok, runs} ->
      case Map.get(previous, ref.contact_planning_run_id) do
        %{lifecycle_state: state} = run
        when state in [:completed, :partial, :failed] and
               run.contact_requirement_id == ref.contact_requirement_id and
               run.contact_requirement_version == ref.contact_requirement_version ->
          {:cont, {:ok, [run | runs]}}

        nil ->
          {:halt, {:error, :contact_planning_run_not_found}}

        _other ->
          {:halt, {:error, :fleet_planning_stage_4_run_binding_mismatch}}
      end
    end)
  end

  defp search_pending(_scope, _run, [], _requirements, _actor, _policy, _opts, summary),
    do: {:ok, summary}

  defp search_pending(scope, run, pending, requirements, actor, policy, opts, summary) do
    by_id = Map.new(requirements, &{&1.contact_requirement_id, &1})
    requirements = Enum.map(pending, &Map.fetch!(by_id, &1.contact_requirement_id))
    spacecraft_ids = requirements |> Enum.map(& &1.spacecraft_id) |> Enum.uniq()

    with {:ok, route_results, providers} <-
           ProviderScheduling.list_ready_downlink_routes_for_fleet(
             run.organization_id,
             run.mission_id,
             spacecraft_ids
           ) do
      context = %{
        actor: actor,
        scope: scope,
        run: run,
        route_results: route_results,
        providers: providers,
        windows: blocking_windows(run, requirements),
        provider_concurrency: policy.horizon_document["provider_search_concurrency"],
        opts: opts
      }

      search_batches(
        requirements,
        context,
        policy.horizon_document["requirement_concurrency"],
        summary
      )
    end
  end

  defp search_batches(requirements, context, concurrency, summary) do
    requirements
    |> Enum.sort_by(&window_key/1)
    |> Stream.chunk_every(@batch_size)
    |> Task.async_stream(&search_batch(&1, context),
      max_concurrency: concurrency,
      timeout: :infinity
    )
    |> Enum.reduce_while({:ok, summary}, fn
      {:ok, {:ok, runs}}, {:ok, summary} -> {:cont, {:ok, add_runs(summary, runs)}}
      {:ok, error}, _summary -> {:halt, error}
      {:exit, _reason}, _summary -> {:halt, {:error, :fleet_requirement_search_worker_exit}}
    end)
  end

  defp window_key(requirement) do
    {DateTime.to_unix(requirement.earliest_start, :microsecond),
     DateTime.to_unix(requirement.latest_end, :microsecond)}
  end

  defp window(requirement), do: {requirement.earliest_start, requirement.latest_end}

  defp blocking_windows(run, requirements) do
    from = Enum.min_by(requirements, & &1.earliest_start, DateTime).earliest_start
    to = Enum.max_by(requirements, & &1.latest_end, DateTime).latest_end
    StationAvailability.blocking_windows(run.organization_id, run.mission_id, from, to)
  end

  defp search_batch(requirements, context) do
    routes =
      requirements
      |> Enum.group_by(&window/1)
      |> Map.new(fn {window, items} ->
        routes =
          items
          |> Enum.flat_map(&Planner.fleet_routes(route_result(context.route_results, &1), &1))
          |> Enum.uniq_by(& &1.route_key)

        {window, routes}
      end)

    search_opts = Planner.provider_options(context.opts)

    responses =
      FleetOpportunitySearch.search(
        routes,
        context.providers,
        context.provider_concurrency,
        search_opts
      )

    with {:ok, entries} <- build_entries(requirements, responses, search_opts[:now], context),
         :ok <- checkpoint_entries(entries, context) do
      {:ok, Enum.map(entries, & &1.run)}
    end
  end

  defp build_entries(requirements, responses, started_at, context) do
    Enum.reduce_while(requirements, {:ok, []}, fn requirement, {:ok, entries} ->
      routes = route_result(context.route_results, requirement)
      window_responses = Map.get(responses, window(requirement), %{})

      case Planner.fleet_entry(
             requirement,
             context.actor,
             routes,
             window_responses,
             context.windows,
             Keyword.put(context.opts, :started_at, started_at)
           ) do
        {:error, reason} -> {:halt, {:error, {:contact_requirement_search_failed, reason}}}
        entry -> {:cont, {:ok, [entry | entries]}}
      end
    end)
  end

  defp checkpoint_entries(entries, context) do
    case FleetPlanningRuns.checkpoint_search_batch(
           context.scope,
           context.run.mission_id,
           context.run.fleet_planning_run_id,
           entries
         ) do
      {:ok, :ok} -> :ok
      error -> error
    end
  end

  defp route_result(results, requirement) do
    Map.get(results, requirement.spacecraft_id, {:error, :spacecraft_not_found})
  end

  defp initial_summary(total) do
    %{
      "requirements_total" => total,
      "requirements_searched" => 0,
      "requirements_failed" => 0,
      "snapshots_considered" => 0,
      "snapshots_selected" => 0
    }
  end

  defp add_runs(summary, runs) do
    Enum.reduce(runs, summary, fn run, acc ->
      state =
        if run.lifecycle_state == :failed,
          do: "requirements_failed",
          else: "requirements_searched"

      acc
      |> Map.update!(state, &(&1 + 1))
      |> Map.update!("snapshots_considered", &(&1 + run.summary_document["opportunity_count"]))
    end)
  end
end
