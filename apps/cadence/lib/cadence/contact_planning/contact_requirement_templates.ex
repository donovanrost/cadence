defmodule Cadence.ContactPlanning.ContactRequirementTemplates do
  @moduledoc "Authorized recurring Requirement Template and occurrence materialization boundary."

  import Ecto.Query

  alias Ecto.{Changeset, Multi}

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.ContactPlanning.PlanUpdates

  alias Cadence.ContactPlanning.{
    ContactRequirementOccurrence,
    ContactRequirements,
    ContactRequirementTemplate,
    ContactRequirementTemplateVersion,
    ContactRequirementVersion,
    RequirementSchedule,
    TemplateDays,
    TemplateSupersession,
    TemplateTargets
  }

  alias Cadence.Missions

  alias Cadence.Management.Contacts.Store.{
    ContactRequirementOccurrenceRow,
    ContactRequirementTemplateRow,
    ContactRequirementTemplateVersionRow
  }

  alias Cadence.Repo

  @document_limit 64 * 1_024

  @doc "Persists prepared occurrence bindings inside the caller's transaction."
  def insert_materialized_occurrences([]), do: :ok

  def insert_materialized_occurrences(items) when is_list(items) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    rows = Enum.map(items, &ContactRequirementOccurrenceRow.insert_attrs(&1.occurrence, now))

    {count, _} =
      Repo.insert_all(ContactRequirementOccurrenceRow, rows, on_conflict: :nothing)

    if count == length(items), do: :ok, else: {:error, :fleet_planning_review_changed}
  end

  @spec create(Scope.t(), binary(), map(), keyword()) ::
          {:ok, ContactRequirementTemplate.t(), ContactRequirementTemplateVersion.t()}
          | {:error, term()}
  def create(%Scope{} = current_scope, mission_id, attrs, opts \\ []) do
    create_unpublished(current_scope, mission_id, attrs, opts)
    |> PlanUpdates.published(current_scope.organization_id, mission_id)
  end

  defp create_unpublished(%Scope{} = current_scope, mission_id, attrs, opts)
       when is_binary(mission_id) and is_map(attrs) and is_list(opts) do
    with {:ok, template, version} <- prepare_create(current_scope, mission_id, attrs, opts) do
      Multi.new()
      |> Multi.insert(:template, ContactRequirementTemplateRow.changeset(template))
      |> Multi.insert(:version, ContactRequirementTemplateVersionRow.changeset(version))
      |> Repo.transaction()
      |> normalize_create_result()
    end
  end

  @doc "Validate and normalize an authorized recurring need without persisting rows."
  def prepare_create(%Scope{} = current_scope, mission_id, attrs, opts \\ [])
      when is_binary(mission_id) and is_map(attrs) and is_list(opts) do
    now = now(opts)

    with :ok <- authorize_manage(current_scope, mission_id),
         {:ok, _mission} <- Missions.fetch_mission(current_scope.organization_id, mission_id),
         {:ok, actor_id} <- actor_id(current_scope),
         template_id <-
           value(
             attrs,
             :contact_requirement_template_id,
             Cadence.Ids.new("contact_requirement_template")
           ),
         {:ok, version} <-
           build_version(
             attrs,
             current_scope.organization_id,
             mission_id,
             template_id,
             1,
             actor_id,
             now
           ),
         :ok <- validate_version(version) do
      template =
        ContactRequirementTemplate.new(%{
          contact_requirement_template_id: template_id,
          organization_id: current_scope.organization_id,
          mission_id: mission_id,
          current_version: 1,
          lifecycle_state: :active,
          created_by: actor_id,
          lifecycle_changed_by: actor_id,
          lifecycle_changed_at: now,
          lifecycle_reason: "created"
        })

      {:ok, template, version}
    end
  end

  @spec version(Scope.t(), binary(), binary(), pos_integer(), map(), keyword()) ::
          {:ok, ContactRequirementTemplate.t(), ContactRequirementTemplateVersion.t()}
          | {:error, term()}
  def version(
        %Scope{} = current_scope,
        mission_id,
        template_id,
        expected_version,
        attrs,
        opts \\ []
      ) do
    version_unpublished(current_scope, mission_id, template_id, expected_version, attrs, opts)
    |> PlanUpdates.published(current_scope.organization_id, mission_id)
  end

  defp version_unpublished(
         %Scope{} = current_scope,
         mission_id,
         template_id,
         expected_version,
         attrs,
         opts
       )
       when is_binary(mission_id) and is_binary(template_id) and is_integer(expected_version) and
              expected_version > 0 and is_map(attrs) and is_list(opts) do
    now = now(opts)

    with :ok <- authorize_manage(current_scope, mission_id),
         {:ok, actor_id} <- actor_id(current_scope) do
      Repo.transaction(fn ->
        version_transaction(
          current_scope.organization_id,
          mission_id,
          template_id,
          expected_version,
          attrs,
          actor_id,
          now
        )
      end)
      |> normalize_version_result()
    end
  end

  @spec activate(Scope.t(), binary(), binary(), pos_integer(), binary(), keyword()) ::
          {:ok, ContactRequirementTemplate.t()} | {:error, term()}
  def activate(scope, mission_id, template_id, expected_version, reason, opts \\ []) do
    activate_unpublished(scope, mission_id, template_id, expected_version, reason, opts)
    |> PlanUpdates.published(scope.organization_id, mission_id)
  end

  defp activate_unpublished(scope, mission_id, template_id, expected_version, reason, opts) do
    transition(scope, mission_id, template_id, expected_version, :active, reason, opts)
  end

  @spec pause(Scope.t(), binary(), binary(), pos_integer(), binary(), keyword()) ::
          {:ok, ContactRequirementTemplate.t()} | {:error, term()}
  def pause(scope, mission_id, template_id, expected_version, reason, opts \\ []) do
    pause_unpublished(scope, mission_id, template_id, expected_version, reason, opts)
    |> PlanUpdates.published(scope.organization_id, mission_id)
  end

  defp pause_unpublished(scope, mission_id, template_id, expected_version, reason, opts) do
    transition(scope, mission_id, template_id, expected_version, :paused, reason, opts)
  end

  @spec close(Scope.t(), binary(), binary(), pos_integer(), binary(), keyword()) ::
          {:ok, ContactRequirementTemplate.t()} | {:error, term()}
  def close(scope, mission_id, template_id, expected_version, reason, opts \\ []) do
    close_unpublished(scope, mission_id, template_id, expected_version, reason, opts)
    |> PlanUpdates.published(scope.organization_id, mission_id)
  end

  defp close_unpublished(scope, mission_id, template_id, expected_version, reason, opts) do
    transition(scope, mission_id, template_id, expected_version, :closed, reason, opts)
  end

  @spec fetch(binary(), binary(), binary()) ::
          {:ok, ContactRequirementTemplate.t(), ContactRequirementTemplateVersion.t()}
          | {:error, term()}
  def fetch(organization_id, mission_id, template_id) do
    case Repo.get_by(ContactRequirementTemplateRow,
           organization_id: organization_id,
           mission_id: mission_id,
           contact_requirement_template_id: template_id
         ) do
      nil ->
        {:error, :contact_requirement_template_not_found}

      row ->
        with {:ok, version} <- fetch_version_row(row, row.current_version) do
          {:ok, ContactRequirementTemplateRow.to_domain(row),
           ContactRequirementTemplateVersionRow.to_domain(version)}
        end
    end
  end

  @spec list(binary(), binary(), keyword()) ::
          [{ContactRequirementTemplate.t(), ContactRequirementTemplateVersion.t()}]
  def list(organization_id, mission_id, opts \\ []) do
    ContactRequirementTemplateRow
    |> join(:inner, [template], version in ContactRequirementTemplateVersionRow,
      on:
        version.organization_id == template.organization_id and
          version.mission_id == template.mission_id and
          version.contact_requirement_template_id ==
            template.contact_requirement_template_id and
          version.version == template.current_version
    )
    |> where(
      [template],
      template.organization_id == ^organization_id and template.mission_id == ^mission_id
    )
    |> maybe_filter_lifecycle(opts[:lifecycle_state])
    |> order_by([template], asc: template.contact_requirement_template_id)
    |> select([template, version], {template, version})
    |> maybe_page(opts[:page])
    |> Repo.all()
    |> Enum.map(fn {template, version} ->
      {ContactRequirementTemplateRow.to_domain(template),
       ContactRequirementTemplateVersionRow.to_domain(version)}
    end)
  end

  @spec list_versions(binary(), binary(), binary()) :: [ContactRequirementTemplateVersion.t()]
  def list_versions(organization_id, mission_id, template_id) do
    ContactRequirementTemplateVersionRow
    |> where(
      [version],
      version.organization_id == ^organization_id and version.mission_id == ^mission_id and
        version.contact_requirement_template_id == ^template_id
    )
    |> order_by([version], desc: version.version)
    |> Repo.all()
    |> Enum.map(&ContactRequirementTemplateVersionRow.to_domain/1)
  end

  @spec list_occurrences(binary(), binary(), binary()) :: [ContactRequirementOccurrence.t()]
  def list_occurrences(organization_id, mission_id, template_id) do
    ContactRequirementOccurrenceRow
    |> where(
      [occurrence],
      occurrence.organization_id == ^organization_id and occurrence.mission_id == ^mission_id and
        occurrence.contact_requirement_template_id == ^template_id
    )
    |> order_by([occurrence], desc: occurrence.occurrence_at)
    |> Repo.all()
    |> Enum.map(&ContactRequirementOccurrenceRow.to_domain/1)
  end

  @doc """
  The generated occurrence rows of `template_id` below version `below_version` for the given
  instants and spacecraft (`TemplateDays`, DECISIONS #86). `lock: true` share-locks them.
  """
  @spec older_occurrence_rows(
          binary(),
          binary(),
          binary(),
          pos_integer(),
          [DateTime.t()],
          [
            binary()
          ],
          boolean()
        ) :: [struct()]
  def older_occurrence_rows(org, mission, template_id, below_version, ats, spacecraft_ids, lock?) do
    query =
      where(
        ContactRequirementOccurrenceRow,
        [o],
        o.organization_id == ^org and o.mission_id == ^mission and
          o.contact_requirement_template_id == ^template_id and
          o.contact_requirement_template_version < ^below_version and
          o.generation_state == "generated" and o.occurrence_at in ^ats and
          o.spacecraft_id in ^spacecraft_ids
      )

    query = if lock?, do: lock(query, "FOR SHARE"), else: query
    Repo.all(query)
  end

  @spec materialize(
          Scope.t(),
          binary(),
          binary(),
          DateTime.t(),
          DateTime.t(),
          keyword()
        ) :: {:ok, [map()]} | {:error, term()}
  def materialize(
        %Scope{} = current_scope,
        mission_id,
        template_id,
        %DateTime{} = from,
        %DateTime{} = until,
        opts \\ []
      ) do
    with :ok <- authorize_operator(current_scope, mission_id),
         {:ok, template, version} <-
           fetch(current_scope.organization_id, mission_id, template_id),
         :ok <- active_template(template),
         {:ok, actor_id} <- actor_id(current_scope),
         targets = targets(version, mission_id, opts),
         now = now(opts),
         {due, _capped} = capped_occurrences(version, from, until, now),
         :ok <- fan_out_bound(length(due) * length(targets)) do
      results =
        for occurrence_at <- due, spacecraft_id <- targets do
          materialize_occurrence(
            current_scope,
            version,
            occurrence_at,
            spacecraft_id,
            actor_id,
            now
          )
        end

      case Enum.find(results, &match?({:error, _}, &1)) do
        nil ->
          # Only the occurrences this run generated: each cancelled slot has its replacement.
          maybe_supersede(current_scope, version, targets, now, due, opts)
          {:ok, Enum.map(results, fn {:ok, result} -> result end)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp maybe_supersede(scope, version, targets, now, occurrences, opts) do
    if Keyword.get(opts, :supersede, true),
      do: TemplateSupersession.supersede(scope, version, targets, now, occurrences)
  end

  # A reviewed fleet start passes the spacecraft it reviewed; otherwise resolve them now.
  defp targets(version, mission_id, opts) do
    Keyword.get_lazy(opts, :targets, fn ->
      TemplateTargets.resolve(version.organization_id, mission_id, version.target_document)
    end)
  end

  # 2,000 spacecraft (the runtime target) × 3 contacts/day × a 7-day horizon = 42,000.
  @default_fan_out_limit 50_000

  @doc """
  Spacecraft × occurrences one template materialization (and one fleet start,
  summed over templates) may generate; over it fails instead of truncating.
  Config `:cadence, :template_fan_out_limit` (default 50,000).
  """
  @spec fan_out_limit() :: pos_integer()
  def fan_out_limit,
    do: Application.get_env(:cadence, :template_fan_out_limit, @default_fan_out_limit)

  defp fan_out_bound(count) do
    if count > fan_out_limit(),
      do: {:error, {:template_fan_out_exceeded, count}},
      else: :ok
  end

  @spec materialize_active(
          Scope.t(),
          binary(),
          DateTime.t(),
          DateTime.t(),
          keyword()
        ) :: {:ok, map()} | {:error, term()}
  def materialize_active(
        %Scope{} = current_scope,
        mission_id,
        %DateTime{} = from,
        %DateTime{} = until,
        opts \\ []
      )
      when is_binary(mission_id) and is_list(opts) do
    with :ok <- authorize_operator(current_scope, mission_id) do
      templates =
        list(current_scope.organization_id, mission_id, lifecycle_state: :active)

      results =
        templates
        |> Task.async_stream(
          fn {template, _version} ->
            {
              template.contact_requirement_template_id,
              materialize(
                current_scope,
                mission_id,
                template.contact_requirement_template_id,
                from,
                until,
                opts
              )
            }
          end,
          ordered: true,
          max_concurrency: Keyword.get(opts, :template_concurrency, 4),
          timeout: :infinity
        )
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, _reason} -> {:worker_exit, {:error, :template_materialization_worker_exit}}
        end)

      summarize_materialization(results, length(templates))
    end
  end

  @doc "Pure occurrence review using the same catch-up bounds as materialization."
  def preview_occurrences(version, from, until, now \\ DateTime.utc_now()),
    do: version |> capped_occurrences(from, until, now) |> elem(0)

  @doc """
  Pure: what a run at `now` generates for `version` over `from..until`, as
  `{occurrences, capped}`. Occurrences are earliest first, at most the catch-up policy's
  `maximum_occurrences_per_run`; `capped` is `%{limit: n, last_at: the last one kept}` when that
  cap cut the range short, else nil.

  `maximum_lookback_seconds` bounds how far into the PAST a catch-up reaches, measured from `now`;
  the future part of the range is always in scope, up to the cap (lead, 11-14). It was measured
  back from `until`, so a horizon longer than the lookback generated only its last part.
  """
  @spec capped_occurrences(map(), DateTime.t(), DateTime.t(), DateTime.t()) ::
          {[DateTime.t()], %{limit: pos_integer(), last_at: DateTime.t()} | nil}
  def capped_occurrences(version, from, until, now) do
    policy = version.catch_up_policy_document
    limit = max(policy["maximum_occurrences_per_run"], 1)
    earliest = DateTime.add(now, -policy["maximum_lookback_seconds"], :second)
    effective_from = if DateTime.before?(from, earliest), do: earliest, else: from

    version.schedule_document
    |> RequirementSchedule.occurrences_between(effective_from, until, limit + 1)
    |> Enum.split(limit)
    |> case do
      {kept, []} -> {kept, nil}
      {kept, _beyond} -> {kept, %{limit: limit, last_at: List.last(kept)}}
    end
  end

  defp materialize_occurrence(scope, version, occurrence_at, spacecraft_id, actor_id, now) do
    Repo.transaction(fn ->
      # DECISIONS #86: one requirement per template day. A day an older version already serves
      # (planned, started) or an operator closed stays as it is; this version generates nothing.
      case day_served_by_older_version(version, occurrence_at, spacecraft_id, now) do
        nil -> insert_occurrence(scope, version, occurrence_at, spacecraft_id, actor_id, now)
        older -> existing_materialization(older)
      end
    end)
    |> normalize_materialization_result()
  end

  # The older version's occurrence when the day is kept or done and this version hasn't
  # generated it already; nil when this version should generate (or already did).
  defp day_served_by_older_version(version, occurrence_at, spacecraft_id, now) do
    own =
      Repo.get_by(ContactRequirementOccurrenceRow,
        organization_id: version.organization_id,
        mission_id: version.mission_id,
        contact_requirement_template_id: version.contact_requirement_template_id,
        contact_requirement_template_version: version.version,
        occurrence_at: occurrence_at,
        spacecraft_id: spacecraft_id
      )

    with nil <- own,
         %{} = days <-
           TemplateDays.classify(
             version.organization_id,
             version.mission_id,
             version.contact_requirement_template_id,
             version.version,
             [{occurrence_at, spacecraft_id}],
             now: now,
             lock: true
           ),
         %{outcome: outcome, prior: %{occurrence: older}} when outcome in [:kept, :done] <-
           days[TemplateDays.key(occurrence_at, spacecraft_id)] do
      older
    else
      _generate -> nil
    end
  end

  defp insert_occurrence(scope, version, occurrence_at, spacecraft_id, actor_id, now) do
    candidate =
      ContactRequirementOccurrence.new(%{
        organization_id: version.organization_id,
        mission_id: version.mission_id,
        contact_requirement_template_id: version.contact_requirement_template_id,
        contact_requirement_template_version: version.version,
        spacecraft_id: spacecraft_id,
        occurrence_at: occurrence_at,
        generation_state: :materializing,
        materialized_by: actor_id,
        materialized_at: now
      })

    {:ok, _candidate_row} =
      candidate
      |> ContactRequirementOccurrenceRow.changeset()
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: [
          :organization_id,
          :mission_id,
          :contact_requirement_template_id,
          :contact_requirement_template_version,
          :occurrence_at,
          :spacecraft_id
        ]
      )

    row = fetch_occurrence_row!(version, occurrence_at, spacecraft_id)

    if row.contact_requirement_occurrence_id == candidate.contact_requirement_occurrence_id do
      create_generated_requirement(scope, version, row, occurrence_at, now)
    else
      existing_materialization(row)
    end
  end

  defp create_generated_requirement(scope, version, row, occurrence_at, now) do
    attrs = generated_requirement_attrs(version, occurrence_at, row.spacecraft_id)

    case ContactRequirements.create(scope, version.mission_id, attrs, now: now) do
      {:ok, requirement, requirement_version} ->
        {:ok, updated} =
          row
          |> ContactRequirementOccurrenceRow.generation_changeset(%{
            generation_state: "generated",
            generated_contact_requirement_id: requirement.contact_requirement_id,
            generated_contact_requirement_version: requirement_version.version,
            error_document: %{},
            materialized_at: now
          })
          |> Repo.update()

        %{
          status: :created,
          occurrence: ContactRequirementOccurrenceRow.to_domain(updated),
          requirement: requirement,
          requirement_version: requirement_version
        }

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp existing_materialization(
         %ContactRequirementOccurrenceRow{
           generation_state: "generated"
         } = row
       ) do
    with {:ok, requirement, _current} <-
           ContactRequirements.fetch(
             row.organization_id,
             row.mission_id,
             row.generated_contact_requirement_id
           ),
         {:ok, generated_version} <-
           ContactRequirements.fetch_version(
             row.organization_id,
             row.mission_id,
             row.generated_contact_requirement_id,
             row.generated_contact_requirement_version
           ) do
      %{
        status: :existing,
        occurrence: ContactRequirementOccurrenceRow.to_domain(row),
        requirement: requirement,
        requirement_version: generated_version
      }
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp existing_materialization(_row),
    do: Repo.rollback(:contact_requirement_occurrence_not_converged)

  defp generated_requirement_attrs(version, occurrence_at, spacecraft_id) do
    {earliest_start, latest_end} =
      RequirementSchedule.window(version.schedule_document, occurrence_at)

    metadata =
      version.requirement_document
      |> Map.get("metadata", %{})
      |> Map.put("generation", %{
        "kind" => "contact_requirement_template",
        "contact_requirement_template_id" => version.contact_requirement_template_id,
        "contact_requirement_template_version" => version.version,
        "occurrence_at" => DateTime.to_iso8601(occurrence_at)
      })

    version.requirement_document
    |> Map.put("spacecraft_id", spacecraft_id)
    |> Map.put("earliest_start", earliest_start)
    |> Map.put("latest_end", latest_end)
    |> Map.put("metadata", metadata)
  end

  defp version_transaction(
         organization_id,
         mission_id,
         template_id,
         expected_version,
         attrs,
         actor_id,
         now
       ) do
    with {:ok, row} <- lock_template(organization_id, mission_id, template_id),
         :ok <- editable_template(row),
         :ok <- expected_version(row, expected_version),
         {:ok, current_row} <- fetch_version_row(row, row.current_version),
         current <- ContactRequirementTemplateVersionRow.to_domain(current_row),
         merged <- merge_version_attrs(current, attrs),
         {:ok, next_version} <-
           build_version(
             merged,
             organization_id,
             mission_id,
             template_id,
             row.current_version + 1,
             actor_id,
             now
           ),
         :ok <- validate_version(next_version),
         {:ok, version_row} <-
           Repo.insert(ContactRequirementTemplateVersionRow.changeset(next_version)),
         {:ok, updated_row} <- update_current_version(row, next_version, actor_id, now) do
      {ContactRequirementTemplateRow.to_domain(updated_row),
       ContactRequirementTemplateVersionRow.to_domain(version_row)}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp merge_version_attrs(current, attrs) do
    # A legacy edit giving only spacecraft_id retargets to that one spacecraft.
    current =
      if match?({:ok, _}, fetch_value(attrs, :spacecraft_id)) and
           fetch_value(attrs, :target_document) == :error,
         do: %{current | target_document: nil},
         else: current

    fields = [
      :name,
      :target_document,
      :spacecraft_id,
      :schedule_document,
      :requirement_document,
      :catch_up_policy_document
    ]

    defaults =
      current
      |> Map.from_struct()
      |> Map.take(fields)

    Enum.reduce(fields, defaults, fn field, merged ->
      case fetch_value(attrs, field) do
        {:ok, value} -> Map.put(merged, field, value)
        :error -> merged
      end
    end)
  end

  defp build_version(attrs, organization_id, mission_id, template_id, version, actor_id, now) do
    {:ok,
     ContactRequirementTemplateVersion.new(
       attrs
       |> Map.put(:contact_requirement_template_version_id, Cadence.Ids.new("template_version"))
       |> Map.put(:contact_requirement_template_id, template_id)
       |> Map.put(:organization_id, organization_id)
       |> Map.put(:mission_id, mission_id)
       |> Map.put(:version, version)
       |> Map.put(:created_by, actor_id)
       |> Map.put(:created_at, now)
       |> Map.put(:content_sha256, nil)
     )}
  rescue
    error in ArgumentError -> {:error, {:invalid_contact_requirement_template, error.message}}
  end

  defp validate_version(version) do
    with :ok <- validate_document_size(version.schedule_document),
         :ok <- validate_document_size(version.requirement_document),
         :ok <- validate_document_size(version.catch_up_policy_document),
         :ok <- validate_spacecraft(version),
         {:ok, requirement} <- build_validation_requirement(version) do
      ContactRequirements.validate_content(requirement)
    end
  end

  defp build_validation_requirement(version) do
    occurrence =
      version.schedule_document["anchor_at"]
      |> DateTime.from_iso8601()
      |> then(fn {:ok, timestamp, _offset} -> timestamp end)

    attrs = generated_requirement_attrs(version, occurrence, validation_spacecraft(version))

    {:ok,
     ContactRequirementVersion.new(
       attrs
       |> Map.put(:contact_requirement_version_id, "template_validation")
       |> Map.put(:contact_requirement_id, "template_validation")
       |> Map.put(:organization_id, version.organization_id)
       |> Map.put(:mission_id, version.mission_id)
       |> Map.put(:version, 1)
       |> Map.put(:created_by, version.created_by)
       |> Map.put(:created_at, version.created_at)
     )}
  rescue
    error in ArgumentError -> {:error, {:invalid_contact_requirement_template, error.message}}
  end

  defp validate_document_size(document) do
    if byte_size(:erlang.term_to_binary(document, [:deterministic])) <= @document_limit,
      do: :ok,
      else: {:error, :contact_requirement_template_document_too_large}
  end

  # Legacy single-spacecraft templates keep their old error; targets report the unknown ids.
  defp validate_spacecraft(version) do
    case TemplateTargets.validate(
           version.organization_id,
           version.mission_id,
           version.target_document
         ) do
      {:error, {:template_target_unknown_spacecraft, _ids}}
      when is_binary(version.spacecraft_id) ->
        {:error, :contact_requirement_template_spacecraft_not_found}

      result ->
        result
    end
  end

  # The content check builds one sample requirement; its spacecraft doesn't affect the content rules.
  defp validation_spacecraft(version) do
    version.spacecraft_id ||
      List.first(Map.get(version.target_document, "spacecraft_ids", [])) ||
      "template_validation"
  end

  defp transition(
         %Scope{} = scope,
         mission_id,
         template_id,
         expected_version,
         state,
         reason,
         opts
       )
       when state in [:active, :paused, :closed] do
    reason = reason |> to_string() |> String.trim()
    now = now(opts)

    with :ok <- authorize_manage(scope, mission_id),
         {:ok, actor_id} <- actor_id(scope),
         :ok <- require_reason(reason) do
      transition_transaction(
        scope.organization_id,
        mission_id,
        template_id,
        expected_version,
        state,
        reason,
        actor_id,
        Keyword.put(opts, :now, now)
      )
    end
  end

  defp transition_transaction(
         organization_id,
         mission_id,
         template_id,
         expected_version,
         state,
         reason,
         actor_id,
         opts
       ) do
    now = now(opts)

    Repo.transaction(fn ->
      with {:ok, row} <- lock_template(organization_id, mission_id, template_id),
           :ok <- expected_version(row, expected_version),
           :ok <- reviewed_evidence(row, opts[:reviewed_evidence]),
           :ok <- allowed_transition(row.lifecycle_state, state),
           {:ok, updated} <- update_lifecycle(row, state, reason, actor_id, now) do
        ContactRequirementTemplateRow.to_domain(updated)
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> normalize_transition_result()
  end

  defp summarize_materialization(results, template_count) do
    case Enum.find(results, fn {_template_id, result} -> match?({:error, _}, result) end) do
      nil ->
        materialization_summary(results, template_count)

      {template_id, {:error, reason}} ->
        {:error, {:contact_requirement_template_materialization_failed, template_id, reason}}
    end
  end

  defp materialization_summary(results, template_count) do
    occurrences =
      Enum.flat_map(results, fn {_template_id, {:ok, materialized}} -> materialized end)

    {:ok,
     %{
       "template_count" => template_count,
       "occurrence_count" => length(occurrences),
       "created_count" => Enum.count(occurrences, &(&1.status == :created)),
       "existing_count" => Enum.count(occurrences, &(&1.status == :existing))
     }}
  end

  defp update_current_version(row, version, actor_id, now) do
    row
    |> ContactRequirementTemplateRow.projection_changeset(%{
      current_version: version.version,
      lifecycle_state: row.lifecycle_state,
      lifecycle_changed_by: actor_id,
      lifecycle_changed_at: now,
      lifecycle_reason: "versioned"
    })
    |> Repo.update()
  end

  defp update_lifecycle(row, state, reason, actor_id, now) do
    row
    |> ContactRequirementTemplateRow.projection_changeset(%{
      current_version: row.current_version,
      lifecycle_state: Atom.to_string(state),
      lifecycle_changed_by: actor_id,
      lifecycle_changed_at: now,
      lifecycle_reason: reason
    })
    |> Repo.update()
  end

  defp fetch_occurrence_row!(version, occurrence_at, spacecraft_id) do
    Repo.get_by!(
      ContactRequirementOccurrenceRow,
      organization_id: version.organization_id,
      mission_id: version.mission_id,
      contact_requirement_template_id: version.contact_requirement_template_id,
      contact_requirement_template_version: version.version,
      occurrence_at: occurrence_at,
      spacecraft_id: spacecraft_id
    )
  end

  defp lock_template(organization_id, mission_id, template_id) do
    case ContactRequirementTemplateRow
         |> where(
           [template],
           template.organization_id == ^organization_id and template.mission_id == ^mission_id and
             template.contact_requirement_template_id == ^template_id
         )
         |> lock("FOR UPDATE")
         |> Repo.one() do
      nil -> {:error, :contact_requirement_template_not_found}
      row -> {:ok, row}
    end
  end

  defp fetch_version_row(row, version) do
    case Repo.get_by(ContactRequirementTemplateVersionRow,
           organization_id: row.organization_id,
           mission_id: row.mission_id,
           contact_requirement_template_id: row.contact_requirement_template_id,
           version: version
         ) do
      nil -> {:error, :contact_requirement_template_version_not_found}
      version_row -> {:ok, version_row}
    end
  end

  defp active_template(%ContactRequirementTemplate{lifecycle_state: :active}), do: :ok
  defp active_template(_template), do: {:error, :contact_requirement_template_not_active}

  defp editable_template(%ContactRequirementTemplateRow{lifecycle_state: "closed"}),
    do: {:error, :contact_requirement_template_closed}

  defp editable_template(_row), do: :ok

  defp expected_version(%ContactRequirementTemplateRow{current_version: version}, version),
    do: :ok

  defp expected_version(_row, _version),
    do: {:error, :stale_contact_requirement_template_version}

  defp allowed_transition("active", :paused), do: :ok
  defp allowed_transition("paused", :active), do: :ok
  defp allowed_transition(state, :closed) when state in ["active", "paused"], do: :ok
  defp allowed_transition(state, state), do: :ok
  defp allowed_transition(_current, _next), do: {:error, :invalid_template_lifecycle_transition}

  defp require_reason(""), do: {:error, :contact_requirement_template_transition_reason_required}
  defp require_reason(_reason), do: :ok

  @doc "Exact immutable-version and mutable-lifecycle evidence for a reviewed template."
  def reference(template, version) do
    %{
      "organization_id" => template.organization_id,
      "mission_id" => template.mission_id,
      "template_id" => template.contact_requirement_template_id,
      "version" => template.current_version,
      "content_sha256" => version.content_sha256,
      "lifecycle_state" => to_string(template.lifecycle_state),
      "lifecycle_changed_at" => DateTime.to_iso8601(template.lifecycle_changed_at),
      "lifecycle_changed_by" => template.lifecycle_changed_by
    }
  end

  defp reviewed_evidence(_row, nil), do: :ok

  defp reviewed_evidence(row, evidence) do
    with {:ok, version} <- fetch_version_row(row, row.current_version),
         true <- reference(row, version) == evidence do
      :ok
    else
      _ -> {:error, :stale_contact_requirement_template_evidence}
    end
  end

  defp maybe_page(query, nil), do: query

  defp maybe_page(query, page) when is_integer(page) and page in 1..1_000_000,
    do: query |> limit(26) |> offset(^((page - 1) * 25))

  defp maybe_filter_lifecycle(query, nil), do: query

  defp maybe_filter_lifecycle(query, state) when state in [:active, :paused, :closed],
    do: where(query, [template], template.lifecycle_state == ^Atom.to_string(state))

  @doc """
  Who may create, version, activate, pause or close a template: `:manage_mission`. The check
  every template write and lifecycle move here makes, and `planning.template.manage`
  (`Cadence.Control.PlanningPolicy.permissions/2`) reports (#1160 row 5).
  """
  @spec authorize_manage(Scope.t(), binary()) :: :ok | {:error, term()}
  def authorize_manage(scope, mission_id) do
    Policy.authorize(scope, :manage_mission, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    })
  end

  defp authorize_operator(scope, mission_id) do
    Policy.authorize(scope, :operate_mission, %{
      organization_id: scope.organization_id,
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

  defp normalize_create_result({:ok, %{template: template, version: version}}) do
    {:ok, ContactRequirementTemplateRow.to_domain(template),
     ContactRequirementTemplateVersionRow.to_domain(version)}
  end

  defp normalize_create_result({:error, _operation, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp normalize_create_result({:error, _operation, reason, _changes}), do: {:error, reason}

  defp normalize_version_result({:ok, {template, version}}),
    do: {:ok, template, version}

  defp normalize_version_result({:error, reason}), do: {:error, reason}

  defp normalize_transition_result({:ok, template}), do: {:ok, template}
  defp normalize_transition_result({:error, reason}), do: {:error, reason}

  defp normalize_materialization_result({:ok, result}), do: {:ok, result}
  defp normalize_materialization_result({:error, reason}), do: {:error, reason}

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)

  defp value(attrs, key, default),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))

  defp fetch_value(attrs, key) do
    cond do
      Map.has_key?(attrs, key) -> {:ok, Map.fetch!(attrs, key)}
      Map.has_key?(attrs, Atom.to_string(key)) -> {:ok, Map.fetch!(attrs, Atom.to_string(key))}
      true -> :error
    end
  end
end
