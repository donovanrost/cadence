defmodule Cadence.ContactPlanning.FleetStartInputs do
  @moduledoc "Bounded, exact input snapshots for reviewed manual fleet starts."
  import Ecto.Query

  alias Cadence.ContactPlanning.{
    ContactPlans,
    ContactRequirementTemplates,
    ContentHash,
    FleetPlanningPolicies,
    TemplateSupersession,
    TemplateTargets
  }

  alias Cadence.Management.Contacts.Store.{
    ContactRequirementOccurrenceRow,
    ContactRequirementRow,
    ContactRequirementTemplateRow,
    ContactRequirementTemplateVersionRow,
    ContactRequirementVersionRow
  }

  alias Cadence.Repo

  def load(scope, mission_id, window, locked \\ false) do
    policy_reader =
      if locked,
        do: &FleetPlanningPolicies.fetch_active_locked/2,
        else: &FleetPlanningPolicies.fetch_active/2

    with {:ok, _, policy} <- policy_reader.(scope.organization_id, mission_id),
         :ok <- horizon(window, policy),
         :ok <- lock_plans_first(scope.organization_id, mission_id, window, locked),
         {:ok, requirements} <- requirements(scope.organization_id, mission_id, window, locked),
         {:ok, templates} <- templates(scope.organization_id, mission_id, window, locked) do
      context = %{organization_id: scope.organization_id, mission_id: mission_id}
      requirements = without_superseded(context, window, requirements, templates, locked)

      snapshot = %{
        context: context,
        window: window,
        policy: policy,
        requirements: requirements,
        templates: templates
      }

      {:ok, Map.put(snapshot, :evidence, evidence(snapshot))}
    end
  end

  # Requirements the start will supersede once the templates' current versions materialize
  # (TemplateSupersession) aren't planned: future, not taken up by a plan, and from an older
  # template version or for a spacecraft the template no longer targets.
  # Lock order is plans, then requirements, everywhere (domain CP3 re-review B): before the
  # claim share-locks the requirements, share-lock the plans that reference generated ones.
  defp lock_plans_first(_org, _mission, _window, false), do: :ok

  defp lock_plans_first(org, mission, window, true) do
    with {:ok, requirements} <- requirements(org, mission, window, false) do
      ids =
        for {requirement, version} <- requirements,
            generated_by(version) != nil,
            do: requirement.contact_requirement_id

      ContactPlans.lock_referencing_plans(org, mission, ids)
    end
  end

  defp without_superseded(_context, _window, requirements, [], _locked), do: requirements

  defp without_superseded(context, window, requirements, templates, locked) do
    now = DateTime.utc_now()

    future =
      requirements
      |> Enum.filter(fn {_requirement, version} ->
        DateTime.after?(version.earliest_start, now)
      end)
      |> Enum.group_by(fn {_requirement, version} -> generated_by(version) end)

    stale =
      templates
      |> Enum.flat_map(fn t ->
        future
        |> Map.get(t.version.contact_requirement_template_id, [])
        |> TemplateSupersession.in_window({window.horizon_start, window.horizon_end})
        |> TemplateSupersession.stale(t.version, MapSet.new(t.spacecraft_ids))
        |> Enum.map(&elem(&1, 0))
      end)

    taken_up =
      ContactPlans.requirements_taken_up(context.organization_id, context.mission_id, stale,
        lock: locked
      )

    excluded = stale |> MapSet.new() |> MapSet.difference(taken_up)

    Enum.reject(requirements, fn {requirement, _version} ->
      MapSet.member?(excluded, requirement.contact_requirement_id)
    end)
  end

  defp generated_by(version),
    do: get_in(version.metadata || %{}, ["generation", "contact_requirement_template_id"])

  def horizon(window, policy) do
    duration = DateTime.diff(window.horizon_end, window.horizon_start, :microsecond)

    cond do
      duration <= 0 ->
        {:error, :fleet_planning_horizon_invalid}

      duration > policy.horizon_document["max_horizon_seconds"] * 1_000_000 ->
        {:error, :fleet_planning_horizon_exceeds_policy}

      true ->
        :ok
    end
  end

  defp requirements(org, mission, window, locked) do
    query =
      ContactRequirementRow
      |> join(:left, [r], v in ContactRequirementVersionRow,
        on:
          v.organization_id == r.organization_id and v.mission_id == r.mission_id and
            v.contact_requirement_id == r.contact_requirement_id and
            v.version == r.current_version
      )
      |> where(
        [r, v],
        r.organization_id == ^org and r.mission_id == ^mission and
          r.lifecycle_state == "active" and
          (is_nil(v.version) or
             (v.earliest_start < ^window.horizon_end and
                v.latest_end > ^window.horizon_start))
      )
      |> order_by([r, v], asc: v.latest_end, asc: r.contact_requirement_id)
      |> limit(10_001)
      |> select([r, v], {r, v})

    query |> maybe_lock(locked) |> Repo.all() |> requirement_versions()
  end

  defp requirement_versions(rows) do
    cond do
      Enum.any?(rows, fn {_, version} -> is_nil(version) end) ->
        {:error, :fleet_planning_requirement_version_unavailable}

      length(rows) > 10_000 ->
        {:error, :fleet_planning_run_requirement_limit_exceeded}

      true ->
        {:ok,
         Enum.map(rows, fn {r, v} ->
           {ContactRequirementRow.to_domain(r), ContactRequirementVersionRow.to_domain(v)}
         end)}
    end
  end

  defp templates(_, _, %{include_recurring: false}, _), do: {:ok, []}

  defp templates(org, mission, window, locked) do
    query =
      ContactRequirementTemplateRow
      |> join(:left, [t], v in ContactRequirementTemplateVersionRow,
        on:
          v.organization_id == t.organization_id and v.mission_id == t.mission_id and
            v.contact_requirement_template_id == t.contact_requirement_template_id and
            v.version == t.current_version
      )
      |> where(
        [t],
        t.organization_id == ^org and t.mission_id == ^mission and t.lifecycle_state == "active"
      )
      |> order_by([t], asc: t.contact_requirement_template_id)
      |> limit(1_001)
      |> select([t, v], {t, v})

    rows = query |> maybe_lock(locked) |> Repo.all()

    cond do
      Enum.any?(rows, fn {_, version} -> is_nil(version) end) ->
        {:error, :fleet_planning_template_version_unavailable}

      length(rows) > 1_000 ->
        {:error, :fleet_planning_template_limit_exceeded}

      true ->
        template_snapshots(rows, window)
    end
  end

  defp template_snapshots(rows, window) do
    Enum.reduce_while(rows, {:ok, [], 0}, fn {t, v}, {:ok, acc, count} ->
      version = ContactRequirementTemplateVersionRow.to_domain(v)

      occurrences =
        ContactRequirementTemplates.preview_occurrences(
          version,
          window.horizon_start,
          window.horizon_end
        )

      targets =
        TemplateTargets.resolve(
          version.organization_id,
          version.mission_id,
          version.target_document
        )

      # A template fans out per targeted spacecraft.
      total = count + length(occurrences) * length(targets)

      if total > ContactRequirementTemplates.fan_out_limit() do
        {:halt, {:error, :fleet_planning_occurrence_limit_exceeded}}
      else
        entry = %{
          template: ContactRequirementTemplateRow.to_domain(t),
          version: version,
          occurrences: occurrences,
          spacecraft_ids: targets,
          existing_occurrences: existing_occurrences(version, occurrences)
        }

        {:cont, {:ok, [entry | acc], total}}
      end
    end)
    |> case do
      {:ok, entries, _} -> {:ok, Enum.reverse(entries)}
      {:error, _} = error -> error
    end
  end

  defp existing_occurrences(version, occurrences) do
    ContactRequirementOccurrenceRow
    |> where(
      [r],
      r.organization_id == ^version.organization_id and
        r.mission_id == ^version.mission_id and
        r.contact_requirement_template_id == ^version.contact_requirement_template_id and
        r.contact_requirement_template_version == ^version.version and
        r.occurrence_at in ^occurrences
    )
    # Stable order: several spacecraft share one occurrence, and the review hashes this list.
    |> order_by([r], asc: r.occurrence_at, asc: r.spacecraft_id)
    |> select([r], %{
      at: r.occurrence_at,
      spacecraft_id: r.spacecraft_id,
      state: r.generation_state,
      requirement_id: r.generated_contact_requirement_id,
      requirement_version: r.generated_contact_requirement_version
    })
    |> Repo.all()
    |> Enum.map(fn row -> Map.put(row, :at, DateTime.to_unix(row.at, :microsecond)) end)
  end

  defp maybe_lock(query, true), do: lock(query, [row], fragment("FOR SHARE OF ?", row))
  defp maybe_lock(query, false), do: query

  defp evidence(snapshot) do
    policy = snapshot.policy

    identity = %{
      "contract_version" => 1,
      "organization_id" => snapshot.context.organization_id,
      "mission_id" => snapshot.context.mission_id,
      "policy_id" => policy.fleet_planning_policy_id,
      "policy_version" => policy.version,
      "policy_sha256" => policy.content_sha256
    }

    hash =
      ContentHash.sha256(%{
        "identity" => identity,
        "window" => window_reference(snapshot.window),
        "requirements" =>
          Enum.map(snapshot.requirements, fn {_, v} ->
            %{id: v.contact_requirement_id, version: v.version, sha256: v.content_sha256}
          end),
        "templates" =>
          Enum.map(snapshot.templates, fn t ->
            %{
              id: t.version.contact_requirement_template_id,
              version: t.version.version,
              sha256: t.version.content_sha256,
              occurrences: Enum.map(t.occurrences, &DateTime.to_iso8601/1),
              spacecraft_ids: t.spacecraft_ids,
              existing_occurrences: t.existing_occurrences
            }
          end)
      })

    Map.put(identity, "input_sha256", hash)
  end

  def window_reference(window),
    do: %{
      "horizon_start" => DateTime.to_iso8601(window.horizon_start),
      "horizon_end" => DateTime.to_iso8601(window.horizon_end),
      "include_recurring" => window.include_recurring
    }
end
