defmodule Cadence.Limits.Definitions do
  @moduledoc "Scoped immutable limit definitions and reviewed append-and-activate operations."

  import Ecto.Query

  alias Cadence.Limits.{Definition, DefinitionLifecycle, DefinitionLock, Facts}
  alias Cadence.Limits.GovernedLimitDefinitionRow, as: Row
  alias Cadence.Persistence.{JsonDocument, OrganizationScope}
  alias Cadence.Platform.EventBus
  alias Cadence.Repo

  def persist(%Definition{} = definition, opts \\ []) do
    with :ok <- Definition.validate(definition) do
      changeset = Row.changeset(definition)
      org = Ecto.Changeset.get_field(changeset, :organization_id)

      DefinitionLock.run(
        org,
        definition.mission_id,
        definition.point_id,
        definition.limit_set_name,
        fn ->
          persist_locked(definition, changeset, org, opts)
        end
      )
      |> published_result(opts)
    end
  end

  def append(org, mission, attrs, expected, opts \\ []) do
    with :ok <- valid_review(expected),
         :ok <- OrganizationScope.validate_mission_scope(org, mission) do
      DefinitionLock.run(org, mission, attrs.point_id, attrs.limit_set_name, fn ->
        append_locked(org, mission, attrs, expected, opts)
      end)
      |> published_result(opts)
    end
  end

  def review(org, mission, point, set, opts \\ []) do
    current =
      scoped(org, mission)
      |> where([d], d.point_id == ^point and d.limit_set_name == ^set)
      |> order_by([d], desc: d.version, asc: d.limit_definition_id)
      |> limit(1)
      |> Repo.one()

    identity = Definition.new(%{mission_id: mission, point_id: point, limit_set_name: set})

    activation_event_id =
      case DefinitionLifecycle.fetch_active_status_for_definition(
             identity,
             Keyword.put(opts, :organization_id, org)
           ) do
        {:ok, active} -> active.limit_definition_lifecycle_event_id
        {:error, :active_limit_definition_not_found} -> nil
      end

    %{
      definition_id: current && current.limit_definition_id,
      version: (current && current.version) || 0,
      activation_event_id: activation_event_id
    }
  end

  def page(org, mission, opts \\ []) do
    search = Keyword.get(opts, :search, "") |> String.downcase()

    latest =
      scoped(org, mission)
      |> distinct([d], d.limit_definition_id)
      |> order_by([d], asc: d.limit_definition_id, desc: d.version)

    from(d in subquery(latest),
      where:
        fragment("strpos(lower(?), ?) > 0", d.point_id, ^search) or
          fragment("strpos(lower(?), ?) > 0", d.limit_set_name, ^search)
    )
    |> paginate(Keyword.get(opts, :page, 1),
      asc: :point_id,
      asc: :limit_set_name,
      asc: :limit_definition_id
    )
  end

  def history(org, mission, id, page) do
    scoped(org, mission)
    |> where([d], d.limit_definition_id == ^id)
    |> paginate(page, desc: :version)
  end

  defp append_locked(org, mission, attrs, expected, opts) do
    current = review(org, mission, attrs.point_id, attrs.limit_set_name, opts)

    if current != expected, do: Repo.rollback(:limit_definition_review_conflict)

    definition =
      Definition.new(
        Map.merge(attrs, %{
          mission_id: mission,
          limit_definition_id:
            current.definition_id || definition_id(attrs.point_id, attrs.limit_set_name),
          version: current.version + 1
        })
      )

    case Definition.validate(definition) do
      :ok -> persist_locked(definition, Row.changeset(definition), org, opts)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp persist_locked(definition, changeset, org, opts) do
    row =
      case Repo.insert(changeset,
             on_conflict: :nothing,
             conflict_target: [:mission_id, :limit_definition_id, :version]
           ) do
        {:ok, %Row{id: nil}} -> existing_row!(definition, org)
        {:ok, row} -> row
        {:error, reason} -> Repo.rollback(reason)
      end

    stored = Row.to_domain(row)

    if document(stored) !== document(definition),
      do: Repo.rollback(:limit_definition_version_conflict)

    case DefinitionLifecycle.record_definition_activation(
           stored,
           row,
           Keyword.put(opts, :publish_facts?, false)
         ) do
      {:ok, event, _active} -> {stored, event}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp existing_row!(definition, org) do
    row =
      scoped(org, definition.mission_id)
      |> where(
        [d],
        d.limit_definition_id == ^definition.limit_definition_id and
          d.version == ^definition.version
      )
      |> Repo.one()

    row || Repo.rollback(:limit_definition_version_conflict)
  end

  # Compare JSON values so map iteration order and atom/string metadata keys do
  # not create false conflicts; return the value represented by the stored row.
  defp document(definition), do: definition |> Map.from_struct() |> JsonDocument.encode()

  defp published_result({:ok, {definition, event}}, opts) do
    if event != :unchanged and
         Keyword.get(opts, :publish_facts?, Keyword.get(opts, :invalidate_runtime_cache?, true)) do
      Facts.publish(Keyword.get(opts, :event_bus, EventBus), event)
    end

    {:ok, definition}
  end

  defp published_result({:error, _} = error, _opts), do: error

  defp valid_review(%{definition_id: nil, version: 0, activation_event_id: nil} = review)
       when map_size(review) == 3, do: :ok

  defp valid_review(%{definition_id: id, version: version, activation_event_id: event} = review)
       when map_size(review) == 3 and is_binary(id) and byte_size(id) > 0 and
              is_integer(version) and version > 0 and (is_nil(event) or is_binary(event)),
       do: :ok

  defp valid_review(_), do: {:error, :limit_definition_review_required}

  defp paginate(query, requested, ordering) do
    total = Repo.aggregate(query, :count)
    page = max(1, min(requested, max(1, ceil(total / 25))))

    items =
      query
      |> order_by(^ordering)
      |> limit(25)
      |> offset(^((page - 1) * 25))
      |> Repo.all()
      |> Enum.map(&Row.to_domain/1)

    %{items: items, total_count: total, page: page}
  end

  defp scoped(nil, mission),
    do: from(d in Row, where: d.mission_id == ^mission and is_nil(d.organization_id))

  defp scoped(org, mission),
    do: from(d in Row, where: d.organization_id == ^org and d.mission_id == ^mission)

  defp definition_id(point, set) do
    digest = :crypto.hash(:sha256, point <> ":" <> set) |> Base.url_encode64(padding: false)
    "limit_definition:#{binary_part(digest, 0, 16)}"
  end
end
