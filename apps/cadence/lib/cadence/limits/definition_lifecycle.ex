defmodule Cadence.Limits.DefinitionLifecycle do
  @moduledoc """
  Durable lifecycle log and active projection for governed limit definitions.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Dashboards.RuntimeInvalidation

  alias Cadence.Limits.{
    ActiveDefinition,
    ActiveLimitDefinitionRow,
    Definition,
    DefinitionLifecycleEvent,
    GovernedLimitDefinitionRow
  }

  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent

  alias Cadence.Persistence.Schemas.LimitDefinitionLifecycleEventRow

  alias Cadence.Repo

  @type record_result ::
          {:ok, DefinitionLifecycleEvent.t(), ActiveDefinition.t()}
          | {:ok, :unchanged, ActiveDefinition.t()}
          | {:error, term()}

  @spec record_definition_activation(Definition.t(), map() | struct(), keyword()) ::
          record_result()
  def record_definition_activation(%Definition{} = definition, persisted_row, opts \\ [])
      when is_list(opts) do
    attrs =
      definition
      |> DefinitionLifecycleEvent.attrs_from_definition(
        Keyword.merge(opts,
          organization_id: get_attr(persisted_row, :organization_id),
          payload: payload_from_definition(definition, persisted_row, opts)
        )
      )

    seed = DefinitionLifecycleEvent.new(attrs)

    Repo.transaction(fn ->
      current_row = Repo.get(ActiveLimitDefinitionRow, seed.definition_activation_key)
      current_status = current_row && ActiveLimitDefinitionRow.to_domain(current_row)

      if same_definition?(current_status, seed) do
        touch_status!(current_row, seed)
      else
        record_transition!(attrs, seed, current_status)
      end
    end)
    |> case do
      {:ok, {:changed, event, status}} ->
        maybe_invalidate_limit_definition(event, opts)
        {:ok, event, status}

      {:ok, {:unchanged, status}} ->
        {:ok, :unchanged, status}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec list_definition_lifecycle_events(binary() | nil, binary() | nil, keyword()) :: [
          DefinitionLifecycleEvent.t()
        ]
  def list_definition_lifecycle_events(organization_id, mission_id, opts \\ [])
      when is_list(opts) do
    limit = Keyword.get(opts, :limit, 100)

    LimitDefinitionLifecycleEventRow
    |> maybe_scope_organization(organization_id)
    |> maybe_scope_mission(mission_id)
    |> maybe_filter(:point_id, Keyword.get(opts, :point_id))
    |> maybe_filter(:limit_set_name, Keyword.get(opts, :limit_set_name))
    |> maybe_filter(:limit_definition_id, Keyword.get(opts, :limit_definition_id))
    |> order_by([row], desc: row.observed_at, desc: row.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&LimitDefinitionLifecycleEventRow.to_domain/1)
  end

  @spec list_active_statuses(binary() | nil, binary() | nil, keyword()) :: [
          ActiveDefinition.t()
        ]
  def list_active_statuses(organization_id, mission_id, opts \\ []) when is_list(opts) do
    ActiveLimitDefinitionRow
    |> maybe_scope_organization(organization_id)
    |> maybe_scope_mission(mission_id)
    |> maybe_filter(:point_id, Keyword.get(opts, :point_id))
    |> maybe_filter(:limit_set_name, Keyword.get(opts, :limit_set_name))
    |> maybe_filter(:scope_type, Keyword.get(opts, :scope_type))
    |> maybe_filter(:scope_ref, Keyword.get(opts, :scope_ref))
    |> maybe_filter(:realm, Keyword.get(opts, :realm))
    |> where([row], is_nil(row.active_to))
    |> order_by([row], asc: row.point_id, asc: row.limit_set_name)
    |> Repo.all()
    |> Enum.map(&ActiveLimitDefinitionRow.to_domain/1)
  end

  @spec fetch_active_status(binary()) ::
          {:ok, ActiveDefinition.t()} | {:error, :active_limit_definition_not_found}
  def fetch_active_status(definition_activation_key) when is_binary(definition_activation_key) do
    case Repo.get(ActiveLimitDefinitionRow, definition_activation_key) do
      nil -> {:error, :active_limit_definition_not_found}
      row -> {:ok, ActiveLimitDefinitionRow.to_domain(row)}
    end
  end

  @spec fetch_active_status_for_definition(Definition.t(), keyword()) ::
          {:ok, ActiveDefinition.t()} | {:error, :active_limit_definition_not_found}
  def fetch_active_status_for_definition(%Definition{} = definition, opts \\ [])
      when is_list(opts) do
    definition
    |> DefinitionLifecycleEvent.attrs_from_definition(opts)
    |> DefinitionLifecycleEvent.definition_activation_key()
    |> fetch_active_status()
  end

  @spec list_active_definitions(binary(), keyword()) :: [Definition.t()]
  def list_active_definitions(mission_id, opts \\ [])
      when is_binary(mission_id) and is_list(opts) do
    nil
    |> list_active_statuses(mission_id, opts)
    |> hydrate_active_definitions()
  end

  @spec list_active_definitions(binary(), binary(), keyword()) :: [Definition.t()]
  def list_active_definitions(organization_id, mission_id, opts)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    organization_id
    |> list_active_statuses(mission_id, opts)
    |> hydrate_active_definitions()
  end

  defp same_definition?(%ActiveDefinition{} = status, %DefinitionLifecycleEvent{} = event) do
    status.limit_definition_id == event.limit_definition_id and
      status.limit_definition_version == event.limit_definition_version and
      status.active_to == event.active_to
  end

  defp same_definition?(_status, _event), do: false

  defp touch_status!(%ActiveLimitDefinitionRow{} = row, %DefinitionLifecycleEvent{} = event) do
    case Repo.update(
           ActiveLimitDefinitionRow.touch_changeset(row, event.observed_at, event.payload)
         ) do
      {:ok, row} ->
        {:unchanged, ActiveLimitDefinitionRow.to_domain(row)}

      {:error, %Changeset{} = changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp record_transition!(attrs, %DefinitionLifecycleEvent{}, current_status) do
    event =
      attrs
      |> Map.merge(previous_attrs(current_status))
      |> Map.put(:event_type, event_type(current_status))
      |> DefinitionLifecycleEvent.new()

    with {:ok, event_row} <- Repo.insert(LimitDefinitionLifecycleEventRow.changeset(event)),
         lifecycle_event <- LimitDefinitionLifecycleEventRow.to_domain(event_row),
         {:ok, %OperationalEvent{}} <-
           persist_limit_definition_operational_event(lifecycle_event),
         {:ok, status_row} <-
           lifecycle_event
           |> ActiveDefinition.from_event(next_transition_count(current_status))
           |> ActiveLimitDefinitionRow.changeset()
           |> Repo.insert(
             on_conflict: {:replace, ActiveLimitDefinitionRow.upsert_fields()},
             conflict_target: :definition_activation_key
           ) do
      {:changed, lifecycle_event, ActiveLimitDefinitionRow.to_domain(status_row)}
    else
      {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp persist_limit_definition_operational_event(%DefinitionLifecycleEvent{} = event) do
    event
    |> OperationalEvent.from_limit_definition_lifecycle_event()
    |> then(&OperationalEvents.persist_event(Repo, &1))
  end

  defp previous_attrs(nil), do: %{}

  defp previous_attrs(%ActiveDefinition{} = status) do
    %{
      previous_limit_definition_id: status.limit_definition_id,
      previous_limit_definition_version: status.limit_definition_version
    }
  end

  defp event_type(nil), do: :registered
  defp event_type(%ActiveDefinition{}), do: :activated

  defp next_transition_count(nil), do: 1
  defp next_transition_count(%ActiveDefinition{transition_count: count}), do: count + 1

  defp maybe_invalidate_limit_definition(%DefinitionLifecycleEvent{} = event, opts) do
    config = Application.get_env(:cadence, :dashboard_runtime_invalidation, [])

    if Keyword.get(config, :enabled?, true) and
         Keyword.get(opts, :invalidate_runtime_cache?, true) do
      RuntimeInvalidation.limit_definition_changed(
        %{
          organization_id: event.organization_id,
          mission_id: event.mission_id,
          observable: event.point_id,
          limit_set_name: event.limit_set_name,
          scope_type: event.scope_type,
          scope_ref: event.scope_ref,
          realm: event.realm,
          limit_definition_lifecycle_event_id: event.limit_definition_lifecycle_event_id,
          limit_definition_id: event.limit_definition_id,
          limit_definition_version: event.limit_definition_version,
          evidence_ref: %{
            kind: "limit_definition_lifecycle_event",
            id: event.limit_definition_lifecycle_event_id
          }
        },
        runtime_cache: Keyword.get(config, :runtime_cache, Cadence.Dashboards.RuntimeCache)
      )
    end

    :ok
  end

  defp hydrate_active_definitions(statuses) do
    statuses
    |> Enum.map(&hydrate_active_definition/1)
    |> Enum.reject(&is_nil/1)
  end

  defp hydrate_active_definition(%ActiveDefinition{} = status) do
    GovernedLimitDefinitionRow
    |> where(
      [row],
      row.mission_id == ^status.mission_id and
        row.limit_definition_id == ^status.limit_definition_id and
        row.version == ^status.limit_definition_version
    )
    |> maybe_scope_organization(status.organization_id)
    |> Repo.one()
    |> case do
      nil ->
        nil

      %GovernedLimitDefinitionRow{} = row ->
        row
        |> GovernedLimitDefinitionRow.to_domain()
        |> put_lifecycle_metadata(status)
    end
  end

  defp put_lifecycle_metadata(%Definition{} = definition, %ActiveDefinition{} = status) do
    lifecycle_metadata = %{
      "definition_activation_key" => status.definition_activation_key,
      "limit_definition_lifecycle_event_id" => status.limit_definition_lifecycle_event_id,
      "limit_activation_event_id" => status.limit_definition_lifecycle_event_id,
      "limit_activation_event_type" => Atom.to_string(status.event_type),
      "active_from" => DateTime.to_iso8601(status.active_from)
    }

    %Definition{definition | metadata: Map.merge(definition.metadata || %{}, lifecycle_metadata)}
  end

  defp payload_from_definition(%Definition{} = definition, persisted_row, opts) do
    %{
      source: Keyword.get(opts, :source, "governance.persist_limit_definition"),
      limit_definition_id: definition.limit_definition_id,
      limit_definition_version: definition.version,
      persisted_row_id: get_attr(persisted_row, :id)
    }
  end

  defp maybe_scope_organization(query, nil), do: query

  defp maybe_scope_organization(query, organization_id) when is_binary(organization_id) do
    where(query, [row], row.organization_id == ^organization_id)
  end

  defp maybe_scope_mission(query, nil), do: query

  defp maybe_scope_mission(query, mission_id) when is_binary(mission_id) do
    where(query, [row], row.mission_id == ^mission_id)
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, _field, ""), do: query

  defp maybe_filter(query, field, value) when is_atom(field) do
    where(query, [row], field(row, ^field) == ^enum_string(value))
  end

  defp enum_string(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_string(value), do: value

  defp get_attr(attrs, key, default \\ nil)

  defp get_attr(%_{} = attrs, key, default) when is_atom(key) do
    attrs
    |> Map.from_struct()
    |> get_attr(key, default)
  end

  defp get_attr(attrs, key, default) when is_map(attrs) and is_atom(key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp get_attr(_attrs, _key, default), do: default
end
