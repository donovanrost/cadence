defmodule Cadence.ContactPlanning.FleetStartInputs do
  @moduledoc "Bounded, exact input snapshots for reviewed manual fleet starts."
  import Ecto.Query

  alias Cadence.ContactPlanning.{
    ContactPlans,
    ContactRequirementTemplates,
    ContentHash,
    FleetPlanningPolicies,
    FleetPlanningRuns,
    TemplateDays,
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

  @doc """
  The reviewed inputs. `as_of` is the instant that decides which requirements are still in the
  future (and so get superseded): a preview takes now, and a start passes its review's `as_of`,
  so the review hash doesn't drift with the wall clock between the two (G1).
  """
  def load(scope, mission_id, window, locked \\ false, as_of \\ nil) do
    as_of = as_of || DateTime.truncate(DateTime.utc_now(), :second)

    policy_reader =
      if locked,
        do: &FleetPlanningPolicies.fetch_active_locked/2,
        else: &FleetPlanningPolicies.fetch_active/2

    with {:ok, _, policy} <- policy_reader.(scope.organization_id, mission_id),
         :ok <- horizon(window, policy),
         :ok <- lock_plans_first(scope.organization_id, mission_id, window, locked),
         {:ok, requirements} <- requirements(scope.organization_id, mission_id, window, locked),
         {:ok, templates} <-
           templates(scope.organization_id, mission_id, window, {locked, as_of}) do
      context = %{organization_id: scope.organization_id, mission_id: mission_id}
      requirements = without_superseded(context, requirements, templates, locked, as_of)

      snapshot = %{
        context: context,
        as_of: as_of,
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

  defp without_superseded(_context, requirements, [], _locked, _as_of),
    do: requirements

  defp without_superseded(context, requirements, templates, locked, now) do
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
        # Exactly the occurrences the start will generate for it (qa #86).
        |> TemplateSupersession.at_occurrences(t.occurrences)
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
      |> limit(^(FleetPlanningRuns.maximum_requirements() + 1))
      |> select([r, v], {r, v})

    query |> maybe_lock(locked) |> Repo.all() |> requirement_versions()
  end

  defp requirement_versions(rows) do
    cond do
      Enum.any?(rows, fn {_, version} -> is_nil(version) end) ->
        {:error, :fleet_planning_requirement_version_unavailable}

      length(rows) > FleetPlanningRuns.maximum_requirements() ->
        {:error, :fleet_planning_run_requirement_limit_exceeded}

      true ->
        {:ok,
         Enum.map(rows, fn {r, v} ->
           {ContactRequirementRow.to_domain(r), ContactRequirementVersionRow.to_domain(v)}
         end)}
    end
  end

  @doc """
  A fleet start's template fan-out over `window` (`%{horizon_start, horizon_end}`) at `as_of`,
  without reading any requirement or occurrence rows: one target resolution per active template
  plus schedule arithmetic. `count` is the gross fan-out the start's limit check uses (days that
  already have a requirement included), `limit` that limit, and `capped` the templates whose
  per-run cap cuts the window short, with the last occurrence kept (U52).
  """
  @spec estimate(binary(), binary(), map(), DateTime.t() | nil) ::
          {:ok,
           %{
             count: non_neg_integer(),
             limit: pos_integer(),
             capped: [%{template_id: binary(), limit: pos_integer(), last_at: DateTime.t()}]
           }}
          | {:error, term()}
  def estimate(org, mission, window, as_of \\ nil) do
    as_of = as_of || DateTime.truncate(DateTime.utc_now(), :second)

    with {:ok, rows} <- active_template_rows(org, mission, false) do
      planned = Enum.map(rows, &fan_out(&1, window, as_of))

      {:ok,
       %{
         count: fan_out_count(planned),
         limit: ContactRequirementTemplates.fan_out_limit(),
         capped:
           for %{capped: %{} = capped} = p <- planned do
             %{
               template_id: p.version.contact_requirement_template_id,
               limit: capped.limit,
               last_at: capped.last_at
             }
           end
       }}
    end
  end

  defp templates(_, _, %{include_recurring: false}, _), do: {:ok, []}

  defp templates(org, mission, window, {locked, as_of}) do
    with {:ok, rows} <- active_template_rows(org, mission, locked) do
      template_snapshots(rows, window, {locked, as_of})
    end
  end

  defp active_template_rows(org, mission, locked) do
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
        {:ok, rows}
    end
  end

  # The full fan-out is counted before any existing rows are read, so an over-limit start reports
  # its whole count (U52: {count, limit}, not the first template over it).
  defp template_snapshots(rows, window, {locked, as_of}) do
    planned = Enum.map(rows, &fan_out(&1, window, as_of))
    count = fan_out_count(planned)
    limit = ContactRequirementTemplates.fan_out_limit()

    if count > limit do
      {:error, {:fleet_planning_occurrence_limit_exceeded, count, limit}}
    else
      {:ok, Enum.map(planned, &snapshot_entry(&1, {locked, as_of}))}
    end
  end

  # One template's run over the window at `as_of`: its occurrences (earliest first, capped per
  # run, the lookback measured from as_of) and its targets.
  defp fan_out({t, v}, window, as_of) do
    version = ContactRequirementTemplateVersionRow.to_domain(v)

    {occurrences, capped} =
      ContactRequirementTemplates.capped_occurrences(
        version,
        window.horizon_start,
        window.horizon_end,
        as_of
      )

    %{
      template_row: t,
      version: version,
      occurrences: occurrences,
      capped: capped,
      spacecraft_ids:
        TemplateTargets.resolve(
          version.organization_id,
          version.mission_id,
          version.target_document
        )
    }
  end

  # A template fans out per targeted spacecraft.
  defp fan_out_count(planned),
    do: planned |> Enum.map(&(length(&1.occurrences) * length(&1.spacecraft_ids))) |> Enum.sum()

  defp snapshot_entry(planned, lock) do
    %{
      template: ContactRequirementTemplateRow.to_domain(planned.template_row),
      version: planned.version,
      occurrences: planned.occurrences,
      spacecraft_ids: planned.spacecraft_ids,
      existing_occurrences:
        existing_occurrences(planned.version, planned.occurrences, planned.spacecraft_ids, lock)
    }
  end

  # The template's days that already have a requirement, one row per (at, spacecraft) in a
  # stable order (the review hashes this list; sorted in Elixir, #56): this version's own
  # occurrences, and for the other days, the older version's requirement with what DECISIONS #86
  # decides for it (kept, done, or generate). A kept day that flips (its plan rejected) changes
  # the hash, so the start re-reviews instead of booking a day the review said was kept.
  defp existing_occurrences(version, occurrences, targets, {locked, as_of}) do
    own =
      ContactRequirementOccurrenceRow
      |> where(
        [r],
        r.organization_id == ^version.organization_id and
          r.mission_id == ^version.mission_id and
          r.contact_requirement_template_id == ^version.contact_requirement_template_id and
          r.contact_requirement_template_version == ^version.version and
          r.occurrence_at in ^occurrences
      )
      |> select([r], %{
        at: r.occurrence_at,
        spacecraft_id: r.spacecraft_id,
        state: r.generation_state,
        requirement_id: r.generated_contact_requirement_id,
        requirement_version: r.generated_contact_requirement_version
      })
      |> maybe_lock(locked)
      |> Repo.all()
      |> Enum.map(fn row -> Map.put(row, :at, DateTime.to_unix(row.at, :microsecond)) end)

    own_days = MapSet.new(own, &{&1.at, &1.spacecraft_id})

    other_days =
      for at <- occurrences,
          spacecraft_id <- targets,
          not MapSet.member?(own_days, TemplateDays.key(at, spacecraft_id)),
          do: {at, spacecraft_id}

    older =
      version.organization_id
      |> TemplateDays.classify(
        version.mission_id,
        version.contact_requirement_template_id,
        version.version,
        other_days,
        now: as_of,
        lock: locked
      )
      |> Enum.flat_map(fn
        {_day, %{prior: nil}} -> []
        {{at, spacecraft_id}, day} -> [older_row(at, spacecraft_id, day)]
      end)

    Enum.sort_by(own ++ older, &{&1.at, &1.spacecraft_id})
  end

  defp older_row(at, spacecraft_id, %{outcome: outcome, why: why, prior: prior}) do
    %{
      at: at,
      spacecraft_id: spacecraft_id,
      state: prior.occurrence.generation_state,
      requirement_id: prior.requirement_id,
      requirement_version: prior.occurrence.generated_contact_requirement_version,
      requirement_current_version: prior.requirement_version,
      template_version: prior.template_version,
      outcome: Atom.to_string(outcome),
      why: why && Atom.to_string(why)
    }
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
      "policy_sha256" => policy.content_sha256,
      "as_of" => DateTime.to_iso8601(snapshot.as_of)
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
