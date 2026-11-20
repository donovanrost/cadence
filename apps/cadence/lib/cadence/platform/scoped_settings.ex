defmodule Cadence.Platform.ScopedSettings do
  @moduledoc """
  Versioned storage for domain-owned organization defaults and mission overrides.

  A mission override stores only the paths it sets (per-field, BACKLOG §4): its effective value is
  the organization's merged with them, so every other field follows the organization. `value`
  nil inherits the whole section.
  """
  import Ecto.Query
  alias Cadence.Ids
  alias Cadence.Platform.ContentHash
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Platform.ScopedSettings.RevisionRow
  alias Cadence.Repo
  alias Ecto.Adapters.SQL

  # The organization and its missions share a section lock. Approval admission
  # uses this same lock so a setting cannot change during its durable effect.
  def with_lock(organization_id, section_id, operation) do
    case Repo.transaction(fn ->
           :ok = section_lock(organization_id, section_id)
           rollback_error(operation.())
         end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Runs `operation` in a transaction holding the section lock SHARED: readers that need the section
  to stay stable don't block each other, while a write (`with_lock/3`, `save`) waits for them and,
  once queued, holds back new readers. The activation policy's order against other locks is
  `Cadence.Governance.ActivationLocks`'.
  """
  def with_shared_lock(organization_id, section_id, operation) do
    case Repo.transaction(fn ->
           :ok = section_lock(organization_id, section_id, :shared)
           rollback_error(operation.())
         end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Takes the section lock inside the caller's transaction, held to its end: `:exclusive` for a
  write, `:shared` for a reader that needs the section stable. Never take it shared and then
  exclusive in one transaction: two such upgraders deadlock.
  """
  @spec section_lock(binary(), binary(), :exclusive | :shared) :: :ok
  def section_lock(organization_id, section_id, mode \\ :exclusive) do
    <<key::signed-64, _::binary>> =
      :crypto.hash(:sha256, :erlang.term_to_binary({__MODULE__, organization_id, section_id}))

    SQL.query!(Repo, lock_sql(mode), [key])
    :ok
  end

  defp lock_sql(:exclusive), do: "SELECT pg_advisory_xact_lock($1::bigint)"
  defp lock_sql(:shared), do: "SELECT pg_advisory_xact_lock_shared($1::bigint)"

  defp rollback_error({:error, reason}), do: Repo.rollback(reason)
  defp rollback_error(result), do: result

  def load(organization_id, mission_id, section_id, default) do
    Map.fetch!(load_many(organization_id, [mission_id], section_id, default), mission_id)
  end

  def load_many(organization_id, mission_ids, section_id, default) do
    keys = Enum.uniq(["organization" | Enum.map(mission_ids, &scope_key/1)])

    # One statement captures both levels, including the absence of an override.
    rows =
      from(row in RevisionRow,
        where: row.organization_id == ^organization_id and row.section_id == ^section_id,
        where: row.scope_key in ^keys,
        distinct: row.scope_key,
        order_by: [asc: row.scope_key, desc: row.version]
      )
      |> Repo.all()
      |> Map.new(&{&1.scope_key, &1})

    Map.new(mission_ids, fn mission ->
      {mission, snapshot(rows, organization_id, mission, section_id, default)}
    end)
  end

  defp snapshot(rows, organization_id, mission_id, section_id, default) do
    scope_key = scope_key(mission_id)
    organization = rows["organization"]
    current = rows[scope_key]
    organization_document = if organization, do: organization.document, else: default
    organization_value = organization_document["value"]
    allow_override = organization_document["allow_override"]
    saved = if current, do: current.document["value"], else: nil
    source = source(mission_id, saved, allow_override)

    %{
      token:
        ContentHash.term_sha256(
          {1, organization_id, scope_key, section_id, organization && organization.revision_id,
           current && current.revision_id, default}
        ),
      version: if(current, do: current.version, else: 0),
      saved: if(is_nil(mission_id), do: organization_value, else: saved),
      effective: effective(source, organization_value, saved),
      organization_default: organization_value,
      allow_override: allow_override,
      source: source
    }
  end

  @doc """
  A mission's effective value for an organization value, its `allow_override` and the mission's
  own saved override (nil when it has none): the rule `load/4` applies (#430: the approval
  setting's save judges a mission change and lists the missions an organization save moves with
  this one function, so they can't disagree).
  """
  @spec effective_for(map() | nil, boolean() | nil, map() | nil) :: map() | nil
  def effective_for(organization_value, allow_override, saved),
    do: effective(source(:mission, saved, allow_override), organization_value, saved)

  defp effective("overridden", organization_value, saved),
    do: Map.merge(organization_value || %{}, saved)

  defp effective(_source, organization_value, _saved), do: organization_value

  # Sections whose saves carry a who-may-change rule of their own (#233: the approval setting is
  # loosened only by an organization admin). `save/8` takes them only with that rule as its
  # `:check` (#429), and `rewrite_override/6`, which runs no such rule, refuses them. Named by id,
  # not module: the platform layer doesn't depend on governance (a test keeps the id in step with
  # ActivationPolicy.section_id/0).
  @rule_guarded_sections ["cadence.governance"]

  @doc "Whether `section_id`'s saves carry a who-may-change rule (#233, #429)."
  @spec rule_guarded?(binary()) :: boolean()
  def rule_guarded?(section_id), do: section_id in @rule_guarded_sections

  @doc """
  Saves a new revision of `section_id` for the organization (`mission_id` nil) or a mission, under
  the section lock (exclusive). `opts`: `:check`, a function of the current snapshot that may
  refuse the change (`:ok` or `{:error, reason}`), run under the lock after the token check, so it
  sees exactly what the save replaces; `:audit`, a function of the current snapshot returning a map
  stored with the revision as its `audit` (for example the before and after values). A
  rule-guarded section (`rule_guarded?/1`) is saved only with a `:check`; without one the answer
  is `{:error, :settings_check_required}` and nothing is locked or written (#429).
  """
  def save(
        organization_id,
        mission_id,
        section_id,
        default,
        expected_token,
        document,
        actor,
        opts \\ []
      ) do
    with :ok <- check_given(section_id, opts) do
      locked_save(
        organization_id,
        mission_id,
        section_id,
        default,
        expected_token,
        document,
        actor,
        opts
      )
    end
  end

  defp locked_save(
         organization_id,
         mission_id,
         section_id,
         default,
         expected_token,
         document,
         actor,
         opts
       ) do
    with_lock(organization_id, section_id, fn ->
      current = load(organization_id, mission_id, section_id, default)
      check = Keyword.get(opts, :check, fn _current -> :ok end)

      with :ok <- current_token(current, expected_token),
           :ok <- overridable(current, mission_id),
           :ok <- check.(current) do
        insert_revision(organization_id, mission_id, section_id, current, document, actor, opts)
      end
    end)
    |> ScopedReadUpdates.publish_result(:settings_changed, organization_id, mission_id)
  end

  # #429: a rule-guarded section without its rule would run no who-may-change check at all. The
  # check must be a function of the snapshot (`check: nil` is no check; lead's review).
  defp check_given(section_id, opts) do
    if rule_guarded?(section_id) and not is_function(Keyword.get(opts, :check), 1),
      do: {:error, :settings_check_required},
      else: :ok
  end

  defp current_token(%{token: token}, token) when is_binary(token), do: :ok
  defp current_token(_current, _expected_token), do: {:error, :settings_changed}

  defp overridable(_current, nil), do: :ok
  defp overridable(%{allow_override: true}, _mission_id), do: :ok
  defp overridable(_current, _mission_id), do: {:error, :settings_enforced_by_organization}

  defp insert_revision(organization_id, mission_id, section_id, current, document, actor, opts) do
    document =
      case Keyword.get(opts, :audit) do
        nil -> document
        audit -> Map.put(document, "audit", audit.(current))
      end

    Repo.insert(
      RevisionRow.changeset(%{
        revision_id: Ids.new("settings_revision"),
        organization_id: organization_id,
        scope_key: scope_key(mission_id),
        section_id: section_id,
        version: current.version + 1,
        document: document,
        actor_id: actor.id,
        actor_name: actor.name
      })
    )
  end

  def history(organization_id, mission_id, section_id) do
    key = scope_key(mission_id)

    from(row in RevisionRow,
      where: row.organization_id == ^organization_id and row.scope_key == ^key,
      where: row.section_id == ^section_id,
      order_by: [desc: row.version],
      limit: 10
    )
    |> Repo.all()
    |> Enum.map(
      &%{
        id: &1.revision_id,
        version: &1.version,
        actor: &1.actor_name,
        saved_at: DateTime.to_iso8601(&1.inserted_at),
        migration: &1.document["migration"],
        audit: &1.document["audit"]
      }
    )
  end

  @doc """
  Every mission's current override that sets something (`value` not nil), for the per-field
  migration: `[%{organization_id, mission_id, section_id, version, value}]`.
  """
  def mission_overrides do
    from(row in RevisionRow,
      where: like(row.scope_key, "mission:%"),
      distinct: [row.organization_id, row.scope_key, row.section_id],
      order_by: [
        asc: row.organization_id,
        asc: row.scope_key,
        asc: row.section_id,
        desc: row.version
      ]
    )
    |> Repo.all()
    |> Enum.filter(&is_map(&1.document["value"]))
    |> Enum.map(
      &%{
        organization_id: &1.organization_id,
        mission_id: String.replace_prefix(&1.scope_key, "mission:", ""),
        section_id: &1.section_id,
        version: &1.version,
        value: &1.document["value"]
      }
    )
  end

  @doc """
  Writes `document` as a mission override's next revision when its latest is still
  `expected_version` (the per-field migration, which has no section default or token at hand);
  else `{:error, :settings_changed}`. A section whose saves carry a who-may-change rule (the
  approval setting) is refused: `{:error, :section_not_rewritable}`.
  """
  def rewrite_override(_organization_id, _mission_id, section_id, _expected, _document, _actor)
      when section_id in @rule_guarded_sections,
      do: {:error, :section_not_rewritable}

  def rewrite_override(organization_id, mission_id, section_id, expected_version, document, actor)
      when is_binary(mission_id) do
    key = scope_key(mission_id)

    with_lock(organization_id, section_id, fn ->
      latest =
        from(row in RevisionRow,
          where: row.organization_id == ^organization_id and row.scope_key == ^key,
          where: row.section_id == ^section_id,
          select: max(row.version)
        )
        |> Repo.one()

      if latest == expected_version do
        Repo.insert(
          RevisionRow.changeset(%{
            revision_id: Ids.new("settings_revision"),
            organization_id: organization_id,
            scope_key: key,
            section_id: section_id,
            version: expected_version + 1,
            document: document,
            actor_id: actor.id,
            actor_name: actor.name
          })
        )
      else
        {:error, :settings_changed}
      end
    end)
    |> ScopedReadUpdates.publish_result(:settings_changed, organization_id, mission_id)
  end

  @migration_note "Settings now follow the organization except the fields set for this mission."
  @migration_governance "Approval settings stay set for this mission, even where they match " <>
                          "the organization."

  @doc """
  The audit's words for a mission the per-field migration rewrote (ux), with the governance
  sentence when it kept approval fields equal to the organization's.
  """
  def migration_note(governance_kept?),
    do:
      if(governance_kept?,
        do: @migration_note <> " " <> @migration_governance,
        else: @migration_note
      )

  defp scope_key(nil), do: "organization"
  defp scope_key(mission_id), do: "mission:#{mission_id}"
  defp source(nil, _saved, _allowed), do: "organization"
  defp source(_mission, _saved, false), do: "enforced"
  defp source(_mission, nil, true), do: "inherited"
  defp source(_mission, _saved, true), do: "overridden"
end
