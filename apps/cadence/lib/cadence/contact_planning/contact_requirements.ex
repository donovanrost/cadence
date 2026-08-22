defmodule Cadence.ContactPlanning.ContactRequirements do
  @moduledoc "Authorized persistence boundary for versioned mission Contact Requirements."

  import Ecto.Query

  alias Ecto.{Changeset, Multi}

  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.ContactPlanning.{
    ContactRequirement,
    ContactRequirementVersion
  }

  alias Cadence.Missions

  alias Cadence.Management.Contacts.Store.{
    ContactRequirementRow,
    ContactRequirementVersionRow
  }

  alias Cadence.Repo
  alias Cadence.SpacecraftStore

  @content_fields [
    :spacecraft_id,
    :service_direction,
    :contact_intent,
    :earliest_start,
    :latest_end,
    :success_measure,
    :minimum_duration_seconds,
    :preferred_duration_seconds,
    :minimum_data_volume_bytes,
    :contact_count,
    :minimum_separation_seconds,
    :priority,
    :provider_constraints_document,
    :station_constraints_document,
    :policy_constraints_document,
    :approval_policy_document,
    :rationale,
    :metadata
  ]

  @numeric_fields [
    :minimum_duration_seconds,
    :preferred_duration_seconds,
    :minimum_data_volume_bytes,
    :contact_count,
    :minimum_separation_seconds
  ]

  @spec create(Scope.t(), binary(), map(), keyword()) ::
          {:ok, ContactRequirement.t(), ContactRequirementVersion.t()} | {:error, term()}
  def create(%Scope{} = current_scope, mission_id, attrs, opts \\ [])
      when is_binary(mission_id) and is_map(attrs) and is_list(opts) do
    now = now(opts)

    with :ok <- authorize_member(current_scope, mission_id),
         {:ok, _mission} <-
           Missions.fetch_mission(current_scope.organization_id, mission_id),
         {:ok, actor_id} <- actor_id(current_scope),
         requirement_id <-
           value(attrs, :contact_requirement_id, Cadence.Ids.new("contact_requirement")),
         {:ok, version} <-
           build_version(
             nil,
             attrs,
             current_scope.organization_id,
             mission_id,
             requirement_id,
             1,
             actor_id,
             now
           ),
         :ok <- validate_spacecraft(version),
         :ok <- validate_content(version) do
      requirement =
        ContactRequirement.new(%{
          contact_requirement_id: requirement_id,
          organization_id: current_scope.organization_id,
          mission_id: mission_id,
          current_version: 1,
          lifecycle_state: :active,
          created_by: actor_id,
          lifecycle_changed_by: actor_id,
          lifecycle_changed_at: now,
          lifecycle_reason: "created"
        })

      Multi.new()
      |> Multi.insert(:requirement, ContactRequirementRow.changeset(requirement))
      |> Multi.insert(:version, ContactRequirementVersionRow.changeset(version))
      |> Repo.transaction()
      |> normalize_create_result()
    end
  end

  @spec version(Scope.t(), binary(), binary(), pos_integer(), map(), keyword()) ::
          {:ok, ContactRequirement.t(), ContactRequirementVersion.t()} | {:error, term()}
  def version(
        %Scope{} = current_scope,
        mission_id,
        requirement_id,
        expected_version,
        attrs,
        opts \\ []
      )
      when is_binary(mission_id) and is_binary(requirement_id) and
             is_integer(expected_version) and expected_version > 0 and is_map(attrs) and
             is_list(opts) do
    now = now(opts)

    with :ok <- authorize_member(current_scope, mission_id),
         {:ok, _mission} <-
           Missions.fetch_mission(current_scope.organization_id, mission_id),
         {:ok, actor_id} <- actor_id(current_scope) do
      Repo.transaction(fn ->
        version_transaction(
          current_scope.organization_id,
          mission_id,
          requirement_id,
          expected_version,
          attrs,
          actor_id,
          now
        )
      end)
      |> normalize_version_result()
    end
  end

  @spec close(Scope.t(), binary(), binary(), pos_integer(), binary(), keyword()) ::
          {:ok, ContactRequirement.t()} | {:error, term()}
  def close(current_scope, mission_id, requirement_id, expected_version, reason, opts \\ []) do
    transition(
      current_scope,
      mission_id,
      requirement_id,
      expected_version,
      :closed,
      reason,
      opts
    )
  end

  @spec cancel(Scope.t(), binary(), binary(), pos_integer(), binary(), keyword()) ::
          {:ok, ContactRequirement.t()} | {:error, term()}
  def cancel(current_scope, mission_id, requirement_id, expected_version, reason, opts \\ []) do
    transition(
      current_scope,
      mission_id,
      requirement_id,
      expected_version,
      :canceled,
      reason,
      opts
    )
  end

  @spec fetch(binary(), binary(), binary()) ::
          {:ok, ContactRequirement.t(), ContactRequirementVersion.t()} | {:error, term()}
  def fetch(organization_id, mission_id, requirement_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(requirement_id) do
    case Repo.get_by(ContactRequirementRow,
           organization_id: organization_id,
           mission_id: mission_id,
           contact_requirement_id: requirement_id
         ) do
      nil ->
        {:error, :contact_requirement_not_found}

      row ->
        with {:ok, version} <-
               fetch_version(organization_id, mission_id, requirement_id, row.current_version) do
          {:ok, ContactRequirementRow.to_domain(row), version}
        end
    end
  end

  @spec fetch_version(binary(), binary(), binary(), pos_integer()) ::
          {:ok, ContactRequirementVersion.t()} | {:error, term()}
  def fetch_version(organization_id, mission_id, requirement_id, version)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(requirement_id) and
             is_integer(version) and version > 0 do
    case Repo.get_by(ContactRequirementVersionRow,
           organization_id: organization_id,
           mission_id: mission_id,
           contact_requirement_id: requirement_id,
           version: version
         ) do
      nil -> {:error, :contact_requirement_version_not_found}
      row -> {:ok, ContactRequirementVersionRow.to_domain(row)}
    end
  end

  @spec list(binary(), binary(), keyword()) ::
          [{ContactRequirement.t(), ContactRequirementVersion.t()}]
  def list(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    ContactRequirementRow
    |> join(:inner, [requirement], version in ContactRequirementVersionRow,
      on:
        version.organization_id == requirement.organization_id and
          version.mission_id == requirement.mission_id and
          version.contact_requirement_id == requirement.contact_requirement_id and
          version.version == requirement.current_version
    )
    |> where(
      [requirement],
      requirement.organization_id == ^organization_id and requirement.mission_id == ^mission_id
    )
    |> maybe_filter_lifecycle(opts[:lifecycle_state])
    |> order_by([requirement, version],
      asc: version.latest_end,
      desc: version.priority,
      asc: requirement.contact_requirement_id
    )
    |> select([requirement, version], {requirement, version})
    |> Repo.all()
    |> Enum.map(fn {requirement, version} ->
      {ContactRequirementRow.to_domain(requirement),
       ContactRequirementVersionRow.to_domain(version)}
    end)
  end

  @spec list_versions(binary(), binary(), binary()) :: [ContactRequirementVersion.t()]
  def list_versions(organization_id, mission_id, requirement_id) do
    ContactRequirementVersionRow
    |> where(
      [version],
      version.organization_id == ^organization_id and version.mission_id == ^mission_id and
        version.contact_requirement_id == ^requirement_id
    )
    |> order_by([version], desc: version.version)
    |> Repo.all()
    |> Enum.map(&ContactRequirementVersionRow.to_domain/1)
  end

  defp transition(
         %Scope{} = current_scope,
         mission_id,
         requirement_id,
         expected_version,
         lifecycle_state,
         reason,
         opts
       )
       when lifecycle_state in [:closed, :canceled] and is_binary(mission_id) and
              is_binary(requirement_id) and is_integer(expected_version) and
              expected_version > 0 and is_list(opts) do
    normalized_reason = reason |> to_string() |> String.trim()
    now = now(opts)

    with :ok <- authorize_member(current_scope, mission_id),
         {:ok, _mission} <-
           Missions.fetch_mission(current_scope.organization_id, mission_id),
         {:ok, actor_id} <- actor_id(current_scope),
         :ok <- required_reason(normalized_reason) do
      Repo.transaction(fn ->
        transition_transaction(
          current_scope.organization_id,
          mission_id,
          requirement_id,
          expected_version,
          lifecycle_state,
          normalized_reason,
          actor_id,
          now
        )
      end)
      |> normalize_transition_result()
    end
  end

  defp version_transaction(
         organization_id,
         mission_id,
         requirement_id,
         expected_version,
         attrs,
         actor_id,
         now
       ) do
    with {:ok, row} <- lock_requirement(organization_id, mission_id, requirement_id),
         :ok <- active_requirement(row),
         :ok <- expected_version(row, expected_version),
         {:ok, current} <- fetch_version_row(row, row.current_version),
         {:ok, next_version} <- build_next_version(row, current, attrs, actor_id, now),
         :ok <- validate_spacecraft(next_version),
         :ok <- validate_content(next_version),
         {:ok, _version_row} <- Repo.insert(ContactRequirementVersionRow.changeset(next_version)),
         {:ok, updated_row} <- update_current_version(row, next_version) do
      {ContactRequirementRow.to_domain(updated_row), next_version}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp build_next_version(row, current, attrs, actor_id, now) do
    build_version(
      ContactRequirementVersionRow.to_domain(current),
      attrs,
      row.organization_id,
      row.mission_id,
      row.contact_requirement_id,
      row.current_version + 1,
      actor_id,
      now
    )
  end

  defp update_current_version(row, next_version) do
    row
    |> ContactRequirementRow.projection_changeset(%{
      current_version: next_version.version,
      lifecycle_state: "active",
      lifecycle_changed_by: row.lifecycle_changed_by,
      lifecycle_changed_at: row.lifecycle_changed_at,
      lifecycle_reason: row.lifecycle_reason
    })
    |> Repo.update()
  end

  defp transition_transaction(
         organization_id,
         mission_id,
         requirement_id,
         expected_version,
         lifecycle_state,
         reason,
         actor_id,
         now
       ) do
    with {:ok, row} <- lock_requirement(organization_id, mission_id, requirement_id),
         :ok <- active_requirement(row),
         :ok <- expected_version(row, expected_version),
         {:ok, updated} <- update_lifecycle(row, lifecycle_state, reason, actor_id, now) do
      ContactRequirementRow.to_domain(updated)
    else
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp update_lifecycle(row, lifecycle_state, reason, actor_id, now) do
    row
    |> ContactRequirementRow.projection_changeset(%{
      current_version: row.current_version,
      lifecycle_state: Atom.to_string(lifecycle_state),
      lifecycle_changed_by: actor_id,
      lifecycle_changed_at: now,
      lifecycle_reason: reason
    })
    |> Repo.update()
  end

  defp build_version(
         previous,
         attrs,
         organization_id,
         mission_id,
         requirement_id,
         version,
         actor_id,
         created_at
       ) do
    defaults = if previous, do: Map.from_struct(previous), else: %{}

    content =
      Enum.reduce(@content_fields, defaults, fn field, acc ->
        case fetch_value(attrs, field) do
          {:ok, item} -> Map.put(acc, field, normalize_input(field, item))
          :error -> acc
        end
      end)

    {:ok,
     ContactRequirementVersion.new(
       Map.merge(content, %{
         contact_requirement_version_id: Cadence.Ids.new("contact_requirement_version"),
         contact_requirement_id: requirement_id,
         organization_id: organization_id,
         mission_id: mission_id,
         version: version,
         created_by: actor_id,
         created_at: created_at,
         content_sha256: nil
       })
     )}
  rescue
    error in ArgumentError -> {:error, {:invalid_contact_requirement, error.message}}
  end

  defp validate_spacecraft(version) do
    case SpacecraftStore.fetch_spacecraft(
           version.organization_id,
           version.mission_id,
           version.spacecraft_id
         ) do
      {:ok, _spacecraft} -> :ok
      {:error, _reason} -> {:error, :contact_requirement_spacecraft_not_found}
    end
  end

  @doc false
  @spec validate_content(ContactRequirementVersion.t()) :: :ok | {:error, term()}
  def validate_content(%ContactRequirementVersion{} = version) do
    with :ok <- validate_text(version.contact_intent, 120, :contact_intent),
         :ok <- validate_text(version.rationale, 2_000, :rationale),
         :ok <- validate_document(version.provider_constraints_document, 16_384),
         :ok <- validate_document(version.station_constraints_document, 16_384),
         :ok <- validate_document(version.policy_constraints_document, 16_384),
         :ok <- validate_document(version.approval_policy_document, 8_192),
         :ok <- validate_document(version.metadata, 32_768),
         :ok <- validate_reference_constraints(version.provider_constraints_document),
         :ok <- validate_reference_constraints(version.station_constraints_document) do
      validate_approval_policy(version.approval_policy_document)
    end
  end

  defp validate_text(item, maximum, field) when is_binary(item) do
    if String.length(item) <= maximum,
      do: :ok,
      else: {:error, {:contact_requirement_field_too_large, field, maximum}}
  end

  defp validate_document(document, maximum) do
    if byte_size(:erlang.term_to_binary(document, [:deterministic])) <= maximum,
      do: :ok,
      else: {:error, :contact_requirement_document_too_large}
  end

  defp validate_reference_constraints(document) do
    allowed = Map.get(document, "allowed", [])
    excluded = Map.get(document, "excluded", [])

    cond do
      not string_list?(allowed) or not string_list?(excluded) ->
        {:error, :invalid_contact_requirement_constraints}

      not MapSet.disjoint?(MapSet.new(allowed), MapSet.new(excluded)) ->
        {:error, :conflicting_contact_requirement_constraints}

      true ->
        :ok
    end
  end

  defp validate_approval_policy(%{"mode" => "manual"}), do: :ok
  defp validate_approval_policy(%{"mode" => "bounded_automatic"}), do: :ok
  defp validate_approval_policy(_document), do: {:error, :unsupported_contact_plan_approval_mode}

  defp string_list?(items),
    do: is_list(items) and Enum.all?(items, &(is_binary(&1) and &1 != ""))

  defp lock_requirement(organization_id, mission_id, requirement_id) do
    case ContactRequirementRow
         |> where(
           [requirement],
           requirement.organization_id == ^organization_id and
             requirement.mission_id == ^mission_id and
             requirement.contact_requirement_id == ^requirement_id
         )
         |> lock("FOR UPDATE")
         |> Repo.one() do
      nil -> {:error, :contact_requirement_not_found}
      row -> {:ok, row}
    end
  end

  defp fetch_version_row(row, version) do
    case Repo.get_by(ContactRequirementVersionRow,
           organization_id: row.organization_id,
           mission_id: row.mission_id,
           contact_requirement_id: row.contact_requirement_id,
           version: version
         ) do
      nil -> {:error, :contact_requirement_version_not_found}
      version_row -> {:ok, version_row}
    end
  end

  defp active_requirement(%ContactRequirementRow{lifecycle_state: "active"}), do: :ok
  defp active_requirement(_row), do: {:error, :contact_requirement_not_active}

  defp expected_version(%ContactRequirementRow{current_version: version}, version), do: :ok
  defp expected_version(_row, _version), do: {:error, :stale_contact_requirement_version}

  defp required_reason(""), do: {:error, :contact_requirement_transition_reason_required}
  defp required_reason(_reason), do: :ok

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

  defp maybe_filter_lifecycle(query, nil), do: query

  defp maybe_filter_lifecycle(query, lifecycle_state)
       when lifecycle_state in [:active, :closed, :canceled] do
    where(query, [requirement], requirement.lifecycle_state == ^Atom.to_string(lifecycle_state))
  end

  defp normalize_create_result({:ok, %{requirement: requirement, version: version}}) do
    {:ok, ContactRequirementRow.to_domain(requirement),
     ContactRequirementVersionRow.to_domain(version)}
  end

  defp normalize_create_result({:error, _operation, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp normalize_create_result({:error, _operation, reason, _changes}), do: {:error, reason}

  defp normalize_version_result({:ok, {requirement, version}}),
    do: {:ok, requirement, version}

  defp normalize_version_result({:error, reason}), do: {:error, reason}

  defp normalize_transition_result({:ok, requirement}), do: {:ok, requirement}
  defp normalize_transition_result({:error, reason}), do: {:error, reason}

  defp normalize_input(field, "") when field in @numeric_fields, do: nil

  defp normalize_input(field, item) when field in @numeric_fields and is_binary(item) do
    case Integer.parse(item) do
      {integer, ""} -> integer
      _other -> item
    end
  end

  defp normalize_input(_field, item), do: item

  defp fetch_value(attrs, key) do
    cond do
      Map.has_key?(attrs, key) -> {:ok, Map.fetch!(attrs, key)}
      Map.has_key?(attrs, Atom.to_string(key)) -> {:ok, Map.fetch!(attrs, Atom.to_string(key))}
      true -> :error
    end
  end

  defp value(attrs, key, default),
    do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))

  defp now(opts),
    do: opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.truncate(:microsecond)
end
