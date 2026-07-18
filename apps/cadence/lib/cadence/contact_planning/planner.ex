defmodule Cadence.ContactPlanning.Planner do
  @moduledoc "Durable bounded multi-provider planning for one exact Contact Requirement version."

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.ContactPlanning.{
    ContactOpportunitySnapshot,
    ContactPlanningRun,
    ContactPlanningSearch,
    ContactRequirements,
    ContentHash,
    RequirementEvaluator
  }

  alias Cadence.Contacts.ProviderScheduling
  alias Cadence.GroundNetworks.{ProviderError, Validation}
  alias Cadence.Persistence.JsonDocument

  alias Cadence.Persistence.Schemas.{
    ContactOpportunitySnapshotRow,
    ContactPlanningRunRow,
    ContactPlanningSearchRow
  }

  alias Cadence.Repo

  @route_binding_fields [
    :route_key,
    :spacecraft_id,
    :provider_spacecraft_ref,
    :source_endpoint_id,
    :routing_rule_id,
    :link_assignment_id,
    :path_template_id,
    :path_template_version,
    :transport_id,
    :transport_version,
    :provider_id,
    :provider_version,
    :provider_account_id,
    :provider_account_version,
    :provider_account_grant_id,
    :provider_account_grant_version,
    :provider_profile_id,
    :provider_profile_version,
    :service_profile_ref,
    :delivery_profile_ref,
    :delivery_policy_document,
    :provider_display_name,
    :service_display_name,
    :delivery_display_name,
    :route_display_name
  ]

  @spec run(Scope.t(), binary(), binary(), pos_integer(), keyword()) ::
          {:ok,
           %{
             run: ContactPlanningRun.t(),
             searches: [ContactPlanningSearch.t()],
             snapshots: [ContactOpportunitySnapshot.t()]
           }}
          | {:error, term()}
  def run(%Scope{} = current_scope, mission_id, requirement_id, requirement_version, opts \\ [])
      when is_binary(mission_id) and is_binary(requirement_id) and
             is_integer(requirement_version) and requirement_version > 0 and is_list(opts) do
    started_at = now(opts)

    with :ok <- authorize_member(current_scope, mission_id),
         {:ok, requirement, current_version} <-
           ContactRequirements.fetch(
             current_scope.organization_id,
             mission_id,
             requirement_id
           ),
         :ok <- active_requirement(requirement.lifecycle_state),
         :ok <- current_requirement_version(requirement.current_version, requirement_version),
         :ok <- executable_direction(current_version.service_direction),
         {:ok, actor_id} <- actor_id(current_scope),
         run =
           ContactPlanningRun.new(%{
             organization_id: current_scope.organization_id,
             mission_id: mission_id,
             contact_requirement_id: requirement_id,
             contact_requirement_version: requirement_version,
             lifecycle_state: :running,
             requested_by: actor_id,
             started_at: started_at,
             summary_document: %{}
           }),
         {:ok, _run_row} <- Repo.insert(ContactPlanningRunRow.changeset(run)) do
      execute_run(run, current_version, opts)
    end
  end

  defp execute_run(run, requirement, opts) do
    case list_routes(requirement, opts) do
      {:ok, route_result} ->
        results = search_routes(route_result.routes, requirement, opts)
        completed_at = now(opts)

        case persist_results(
               run,
               requirement,
               route_result.findings,
               results,
               completed_at
             ) do
          {:ok, persisted} -> {:ok, persisted}
          {:error, reason} -> fail_run(run, reason, completed_at)
        end

      {:error, reason} ->
        fail_run(run, reason, now(opts))
    end
  end

  @spec fetch_run(binary(), binary(), binary()) ::
          {:ok, ContactPlanningRun.t()} | {:error, :contact_planning_run_not_found}
  def fetch_run(organization_id, mission_id, run_id) do
    case Repo.get_by(ContactPlanningRunRow,
           organization_id: organization_id,
           mission_id: mission_id,
           contact_planning_run_id: run_id
         ) do
      nil -> {:error, :contact_planning_run_not_found}
      row -> {:ok, ContactPlanningRunRow.to_domain(row)}
    end
  end

  @spec list_runs(binary(), binary(), binary()) :: [ContactPlanningRun.t()]
  def list_runs(organization_id, mission_id, requirement_id) do
    ContactPlanningRunRow
    |> where(
      [run],
      run.organization_id == ^organization_id and run.mission_id == ^mission_id and
        run.contact_requirement_id == ^requirement_id
    )
    |> order_by([run], desc: run.started_at)
    |> Repo.all()
    |> Enum.map(&ContactPlanningRunRow.to_domain/1)
  end

  @spec list_searches(binary(), binary(), binary()) :: [ContactPlanningSearch.t()]
  def list_searches(organization_id, mission_id, run_id) do
    ContactPlanningSearchRow
    |> where(
      [search],
      search.organization_id == ^organization_id and search.mission_id == ^mission_id and
        search.contact_planning_run_id == ^run_id
    )
    |> order_by([search], asc: search.route_order, asc: search.route_key)
    |> Repo.all()
    |> Enum.map(&ContactPlanningSearchRow.to_domain/1)
  end

  @spec list_snapshots(binary(), binary(), binary()) :: [ContactOpportunitySnapshot.t()]
  def list_snapshots(organization_id, mission_id, run_id) do
    ContactOpportunitySnapshotRow
    |> where(
      [snapshot],
      snapshot.organization_id == ^organization_id and snapshot.mission_id == ^mission_id and
        snapshot.contact_planning_run_id == ^run_id
    )
    |> order_by([snapshot], asc: snapshot.starts_at, asc: snapshot.provider_opportunity_ref)
    |> Repo.all()
    |> Enum.map(&ContactOpportunitySnapshotRow.to_domain/1)
  end

  defp list_routes(requirement, opts) do
    routes_fun =
      Keyword.get(
        opts,
        :list_routes,
        &ProviderScheduling.list_ready_downlink_routes/3
      )

    case routes_fun.(
           requirement.organization_id,
           requirement.mission_id,
           requirement.spacecraft_id
         ) do
      {:ok, %{routes: routes, findings: findings}} when is_list(routes) and is_list(findings) ->
        {:ok,
         %{
           routes: Enum.sort_by(routes, &route_sort_key/1),
           findings: Enum.sort_by(findings, &finding_sort_key/1)
         }}

      {:error, reason} ->
        {:error, {:contact_planning_route_resolution_failed, safe_error(reason)}}

      _other ->
        {:error, :contact_planning_route_resolution_malformed}
    end
  end

  defp search_routes(routes, requirement, opts) do
    search_fun =
      Keyword.get(opts, :search_opportunities, &ProviderScheduling.search_opportunities/5)

    search_opts =
      opts
      |> Keyword.get(:provider_opts, [])
      |> Keyword.take([
        :client,
        :credential_resolver,
        :receive_timeout,
        :req_request,
        :secret_backend
      ])
      |> Keyword.merge(Keyword.take(opts, [:result_limit, :now]))
      |> Keyword.put_new(:now, now(opts))

    maximum = Keyword.get(opts, :max_concurrency, 4)

    routes
    |> Task.async_stream(
      &search_route(&1, requirement, search_fun, search_opts),
      ordered: true,
      max_concurrency: maximum,
      timeout: :infinity
    )
    |> Enum.zip(routes)
    |> Enum.map(fn
      {{:ok, result}, _route} ->
        result

      {{:exit, _reason}, route} ->
        %{
          route: route,
          outcome: :failed,
          opportunities: [],
          readiness: %{},
          error: %{"code" => "search_worker_exit"}
        }
    end)
  end

  defp search_route(route, requirement, search_fun, search_opts) do
    if route_excluded?(requirement, route) do
      excluded_search_result(route)
    else
      route
      |> execute_route_search(requirement, search_fun, search_opts)
      |> normalize_route_search(route)
    end
  end

  defp execute_route_search(route, requirement, search_fun, search_opts) do
    search_fun.(
      requirement.organization_id,
      requirement.mission_id,
      route.route_key,
      search_window(requirement),
      search_opts
    )
  end

  defp search_window(requirement) do
    %{
      "spacecraft_id" => requirement.spacecraft_id,
      "starts_at" => DateTime.to_iso8601(requirement.earliest_start),
      "ends_at" => DateTime.to_iso8601(requirement.latest_end)
    }
  end

  defp normalize_route_search(
         {:ok, %{opportunities: opportunities} = response},
         route
       )
       when is_list(opportunities) do
    %{
      route: route,
      outcome: search_success_outcome(opportunities),
      opportunities: opportunities,
      readiness:
        response
        |> Map.get(:provider_evidence, Map.get(response, "provider_evidence", %{}))
        |> Validation.sanitize(),
      error: %{}
    }
  end

  defp normalize_route_search({:error, reason}, route) do
    %{
      route: route,
      outcome: provider_failure_outcome(reason),
      opportunities: [],
      readiness: readiness_from_error(reason),
      error: safe_error(reason)
    }
  end

  defp normalize_route_search(_result, route) do
    %{
      route: route,
      outcome: :failed,
      opportunities: [],
      readiness: %{},
      error: %{"code" => "malformed_search_result"}
    }
  end

  defp excluded_search_result(route) do
    %{
      route: route,
      outcome: :excluded_by_requirement,
      opportunities: [],
      readiness: %{},
      error: %{}
    }
  end

  defp search_success_outcome([]), do: :succeeded_without_results
  defp search_success_outcome(_opportunities), do: :succeeded_with_results

  defp persist_results(run, requirement, findings, results, completed_at) do
    Repo.transaction(fn ->
      readiness = build_readiness_searches(run, findings, completed_at)

      searched =
        results
        |> Enum.with_index(length(readiness))
        |> Enum.map(fn {result, index} ->
          build_search_and_snapshots(run, requirement, result, index, completed_at)
        end)

      all = readiness ++ searched
      searches = Enum.map(all, &elem(&1, 0))
      snapshots = Enum.flat_map(all, &elem(&1, 1))

      persisted_searches =
        Enum.map(searches, fn search ->
          search
          |> ContactPlanningSearchRow.changeset()
          |> Repo.insert!()
          |> ContactPlanningSearchRow.to_domain()
        end)

      persisted_snapshots =
        Enum.map(snapshots, fn snapshot ->
          snapshot
          |> ContactOpportunitySnapshotRow.changeset()
          |> Repo.insert!()
          |> ContactOpportunitySnapshotRow.to_domain()
        end)

      summary = summary(persisted_searches, persisted_snapshots)
      lifecycle_state = run_state(persisted_searches)

      run_row = Repo.get!(ContactPlanningRunRow, run.contact_planning_run_id)

      updated_run =
        run_row
        |> ContactPlanningRunRow.completion_changeset(%{
          lifecycle_state: Atom.to_string(lifecycle_state),
          completed_at: completed_at,
          summary_document: JsonDocument.wrap_value(summary)
        })
        |> Repo.update!()
        |> ContactPlanningRunRow.to_domain()

      %{
        run: updated_run,
        searches: persisted_searches,
        snapshots:
          Enum.sort_by(
            persisted_snapshots,
            &{&1.starts_at, &1.provider_opportunity_ref}
          )
      }
    end)
  rescue
    error in [ArgumentError, Ecto.InvalidChangesetError] ->
      {:error, {:contact_planning_persistence_failed, Exception.message(error)}}
  end

  defp fail_run(run, reason, completed_at) do
    failure = safe_error(reason)

    summary = %{
      "search_count" => 0,
      "search_outcomes" => %{},
      "opportunity_count" => 0,
      "eligible_opportunity_count" => 0,
      "ineligible_opportunity_count" => 0,
      "failure" => failure
    }

    case Repo.get(ContactPlanningRunRow, run.contact_planning_run_id) do
      nil ->
        {:error, :contact_planning_run_not_found}

      row ->
        row
        |> ContactPlanningRunRow.completion_changeset(%{
          lifecycle_state: "failed",
          completed_at: completed_at,
          summary_document: JsonDocument.wrap_value(summary)
        })
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            {:ok,
             %{
               run: ContactPlanningRunRow.to_domain(updated),
               searches: [],
               snapshots: []
             }}

          {:error, update_error} ->
            {:error, {:contact_planning_failure_persistence_failed, update_error}}
        end
    end
  end

  defp build_readiness_searches(run, findings, completed_at) do
    findings
    |> Enum.with_index()
    |> Enum.map(fn {finding, index} ->
      readiness = Validation.sanitize(finding)
      route_key = "readiness:#{readiness["code"]}:#{readiness["resource_id"]}:#{index}"
      content = %{"outcome" => "not_ready", "readiness" => readiness}

      search =
        ContactPlanningSearch.new(%{
          contact_planning_run_id: run.contact_planning_run_id,
          organization_id: run.organization_id,
          mission_id: run.mission_id,
          route_key: route_key,
          route_order: index,
          outcome: :not_ready,
          opportunity_count: 0,
          route_binding_document: %{},
          readiness_document: readiness,
          error_document: %{},
          content_sha256: ContentHash.sha256(content),
          started_at: run.started_at,
          completed_at: completed_at
        })

      {search, []}
    end)
  end

  defp build_search_and_snapshots(run, requirement, result, index, completed_at) do
    route = result.route
    route_document = route_binding(route)
    opportunities = normalized_unique_opportunities(result.opportunities, route_document)

    {outcome, error, opportunities} =
      if opportunity_identity_collision?(result.opportunities, route_document) do
        {:failed, %{"code" => "provider_opportunity_identity_collision"}, []}
      else
        {result.outcome, result.error, opportunities}
      end

    search_id = Cadence.Ids.new("planning_search")

    search_content = %{
      "route" => route_document,
      "outcome" => Atom.to_string(outcome),
      "opportunity_count" => length(opportunities),
      "readiness" => result.readiness,
      "error" => error
    }

    search =
      ContactPlanningSearch.new(%{
        contact_planning_search_id: search_id,
        contact_planning_run_id: run.contact_planning_run_id,
        organization_id: run.organization_id,
        mission_id: run.mission_id,
        route_key: route.route_key,
        route_order: index,
        provider_id: route.provider_id,
        provider_version: route.provider_version,
        provider_account_id: Map.get(route, :provider_account_id),
        provider_account_version: Map.get(route, :provider_account_version),
        provider_account_grant_id: Map.get(route, :provider_account_grant_id),
        provider_account_grant_version: Map.get(route, :provider_account_grant_version),
        provider_display_name: route.provider_display_name,
        outcome: outcome,
        opportunity_count: length(opportunities),
        route_binding_document: route_document,
        readiness_document:
          merge_readiness(result.readiness, readiness_from_opportunities(opportunities)),
        error_document: error,
        content_sha256: ContentHash.sha256(search_content),
        started_at: run.started_at,
        completed_at: completed_at
      })

    snapshots =
      Enum.map(opportunities, fn opportunity ->
        evaluation =
          RequirementEvaluator.evaluate_opportunity(
            requirement,
            opportunity,
            route_document,
            now: completed_at
          )

        evidence = Validation.sanitize(opportunity)

        ContactOpportunitySnapshot.new(%{
          contact_planning_run_id: run.contact_planning_run_id,
          contact_planning_search_id: search_id,
          organization_id: run.organization_id,
          mission_id: run.mission_id,
          contact_requirement_id: requirement.contact_requirement_id,
          contact_requirement_version: requirement.version,
          provider_opportunity_ref: opportunity["id"],
          starts_at: parse_datetime!(opportunity["starts_at"]),
          ends_at: parse_datetime!(opportunity["ends_at"]),
          expires_at: parse_datetime!(opportunity["expires_at"]),
          availability: opportunity["availability"],
          estimated_capacity_document: opportunity["estimated_capacity"] || %{},
          synthetic: opportunity["synthetic"],
          route_binding_document: route_document,
          normalized_opportunity_document: opportunity,
          provider_evidence_document: evidence,
          evaluation_document: evaluation,
          eligible: evaluation["eligible"],
          content_sha256:
            ContentHash.sha256(%{"route" => route_document, "opportunity" => evidence}),
          captured_at: completed_at
        })
      end)

    {search, snapshots}
  end

  defp normalized_unique_opportunities(opportunities, route_document) do
    opportunities
    |> Enum.map(&Validation.sanitize/1)
    |> Enum.uniq_by(fn opportunity ->
      {opportunity["id"],
       ContentHash.sha256(%{"route" => route_document, "opportunity" => opportunity})}
    end)
    |> Enum.sort_by(&{&1["starts_at"], &1["id"]})
  end

  defp opportunity_identity_collision?(opportunities, route_document) do
    opportunities
    |> Enum.map(&Validation.sanitize/1)
    |> Enum.group_by(& &1["id"])
    |> Enum.any?(fn {_id, values} ->
      values
      |> Enum.map(&ContentHash.sha256(%{"route" => route_document, "opportunity" => &1}))
      |> Enum.uniq()
      |> length() > 1
    end)
  end

  @doc "Returns the durable, serializable identity of one ready provider route."
  @spec route_binding(map()) :: map()
  def route_binding(route) when is_map(route) do
    route
    |> Map.take(@route_binding_fields)
    |> JsonDocument.encode()
  end

  defp readiness_from_opportunities(opportunities) do
    opportunities
    |> Enum.map(&get_in(&1, ["extensions", "orbit_readiness"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> then(&%{"orbit_readiness" => &1})
    |> Validation.sanitize()
  end

  defp merge_readiness(provider_evidence, opportunity_evidence) do
    provider_evidence
    |> Validation.sanitize()
    |> Map.merge(opportunity_evidence, fn _key, provider_value, opportunity_value ->
      if provider_value in [nil, %{}, []], do: opportunity_value, else: provider_value
    end)
  end

  defp summary(searches, snapshots) do
    counts = Enum.frequencies_by(searches, &Atom.to_string(&1.outcome))

    %{
      "search_count" => length(searches),
      "search_outcomes" => counts,
      "opportunity_count" => length(snapshots),
      "eligible_opportunity_count" => Enum.count(snapshots, & &1.eligible),
      "ineligible_opportunity_count" => Enum.count(snapshots, &(not &1.eligible))
    }
  end

  defp run_state(searches) do
    failed_count = Enum.count(searches, &(&1.outcome in [:failed, :not_ready]))

    succeeded_count =
      Enum.count(searches, fn search ->
        search.outcome in [:succeeded_with_results, :succeeded_without_results]
      end)

    cond do
      failed_count > 0 and succeeded_count > 0 -> :partial
      failed_count > 0 -> :failed
      true -> :completed
    end
  end

  defp route_excluded?(requirement, route) do
    constraints = requirement.provider_constraints_document
    allowed = Map.get(constraints, "allowed", [])
    excluded = Map.get(constraints, "excluded", [])

    route.provider_id in excluded or (allowed != [] and route.provider_id not in allowed)
  end

  defp route_sort_key(route),
    do: {route.provider_display_name, route.route_display_name, route.route_key}

  defp finding_sort_key(finding),
    do: {to_string(finding[:code]), to_string(finding[:resource_id])}

  defp provider_failure_outcome(%ProviderError{category: :provider_not_ready}), do: :not_ready
  defp provider_failure_outcome(_reason), do: :failed

  defp readiness_from_error(%ProviderError{} = error) do
    error.evidence
    |> get_in(["error", "evidence"])
    |> case do
      evidence when is_map(evidence) -> Validation.sanitize(evidence)
      _other -> %{}
    end
  end

  defp readiness_from_error(_reason), do: %{}

  defp safe_error(%ProviderError{} = error) do
    base = %{
      "code" => Atom.to_string(error.category),
      "category" => to_string(error.category)
    }

    case Validation.sanitize(error.evidence) do
      evidence when is_map(evidence) and map_size(evidence) == 0 -> base
      evidence -> Map.put(base, "provider_evidence", evidence)
    end
  end

  defp safe_error(reason) when is_atom(reason), do: %{"code" => Atom.to_string(reason)}

  defp safe_error({reason, _detail}) when is_atom(reason),
    do: %{"code" => Atom.to_string(reason)}

  defp safe_error(_reason), do: %{"code" => "provider_search_failed"}

  defp parse_datetime!(%DateTime{} = item), do: item

  defp parse_datetime!(item) when is_binary(item) do
    {:ok, parsed, _offset} = DateTime.from_iso8601(item)
    parsed
  end

  defp active_requirement(:active), do: :ok
  defp active_requirement(_state), do: {:error, :contact_requirement_not_active}

  defp current_requirement_version(version, version), do: :ok

  defp current_requirement_version(_current, _requested),
    do: {:error, :stale_contact_requirement_version}

  defp executable_direction(:downlink), do: :ok

  defp executable_direction(_direction),
    do: {:error, :contact_requirement_direction_not_executable}

  defp authorize_member(current_scope, mission_id) do
    Policy.authorize(current_scope, :operate_mission, %{
      organization_id: current_scope.organization_id,
      mission_id: mission_id
    })
  end

  defp actor_id(%Scope{actor_kind: :user, user: %{user_id: user_id}})
       when is_binary(user_id) and user_id != "",
       do: {:ok, user_id}

  defp actor_id(%Scope{
         actor_kind: :service,
         service_identity: %{service_identity_id: service_identity_id}
       })
       when is_binary(service_identity_id) and service_identity_id != "",
       do: {:ok, service_identity_id}

  defp actor_id(%Scope{}), do: {:error, :authenticated_actor_required}

  defp now(opts) do
    case Keyword.get(opts, :now) do
      %DateTime{} = fixed -> DateTime.truncate(fixed, :microsecond)
      nil -> DateTime.utc_now() |> DateTime.truncate(:microsecond)
    end
  end
end
