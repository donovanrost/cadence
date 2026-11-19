defmodule Cadence.Governance.DerivedDefinitions do
  @moduledoc "Scoped immutable derived-definition reads and reviewed version appends."
  import Ecto.Query
  alias Cadence.DerivedTelemetry.Definition
  alias Cadence.Governance.GovernedDerivedTelemetryDefinitionRow, as: Row
  alias Cadence.Missions
  alias Cadence.Platform.SaveTrail
  alias Cadence.Repo
  alias Ecto.Adapters.SQL

  def persist(%Definition{} = definition) do
    with :ok <- Definition.validate(definition) do
      changeset = Row.changeset(definition)
      org = Ecto.Changeset.get_field(changeset, :organization_id)

      transaction(org, definition.mission_id, definition.point_id, fn ->
        persist_locked(changeset, org, definition)
      end)
    end
  end

  def append(org, mission, attrs, expected_version)
      when is_integer(expected_version) and expected_version >= 0 do
    with {:ok, _} <- Missions.fetch_mission(org, mission) do
      transaction(org, mission, attrs.point_id, fn ->
        append_locked(org, mission, attrs, expected_version)
      end)
    end
  end

  def append(_, _, _, _), do: {:error, :derived_definition_review_required}

  # Live definitions only: a retired one (its latest version retired) is left out (#77).
  def list(mission),
    do:
      live(nil, mission)
      |> Repo.all()
      |> Enum.map(&Row.to_domain/1)
      |> Enum.sort_by(& &1.point_id)

  def list(org, mission),
    do:
      live(org, mission)
      |> Repo.all()
      |> Enum.map(&Row.to_domain/1)
      |> Enum.sort_by(& &1.point_id)

  @doc """
  Retires a live definition (#77): appends a final version marked retired, so its history stays.
  `{:ok, definition}` or `{:error, :derived_definition_not_found}`.
  """
  def retire(org, mission, id, actor_id) do
    with {:ok, current} <- fetch_live(org, mission, id) do
      transaction(org, mission, current.point_id, fn ->
        retire_locked(org, mission, id, actor_id)
      end)
    end
  end

  @doc "Whether any version, live or retired, uses `point_id` (a create can't reuse one)."
  def point_used?(org, mission, point_id),
    do: Repo.exists?(scoped(org, mission) |> where([d], d.point_id == ^point_id))

  defp fetch_live(org, mission, id) do
    case live(org, mission) |> where([d], d.derived_definition_id == ^id) |> Repo.one() do
      nil -> {:error, :derived_definition_not_found}
      row -> {:ok, row}
    end
  end

  defp retire_locked(org, mission, id, actor_id) do
    with {:ok, current} <- fetch_live(org, mission, id) do
      %{Row.to_domain(current) | version: current.version + 1}
      |> Row.changeset()
      |> Ecto.Changeset.put_change(:retired_at, DateTime.utc_now())
      |> Ecto.Changeset.put_change(:retired_by, actor_id)
      |> Repo.insert()
      |> case do
        {:ok, row} -> {:ok, Row.to_domain(row)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def page(org, mission, opts) do
    search = Keyword.get(opts, :search, "") |> String.downcase()

    query =
      from(d in live(org, mission),
        where:
          fragment("strpos(lower(?), ?) > 0", d.point_id, ^search) or
            fragment("strpos(lower(?), ?) > 0", d.point_name, ^search)
      )

    paginate(query, Keyword.get(opts, :page, 1), asc: :point_id, asc: :derived_definition_id)
  end

  def history(org, mission, id, page) do
    scoped(org, mission)
    |> where([d], d.derived_definition_id == ^id)
    |> paginate(page, desc: :version)
  end

  def fetch(org, mission, id, version) do
    query = scoped(org, mission) |> where([d], d.derived_definition_id == ^id)

    query =
      if version,
        do: where(query, [d], d.version == ^version),
        else: order_by(query, [d], desc: d.version)

    case query |> limit(1) |> Repo.one() do
      nil -> {:error, :derived_definition_not_found}
      row -> {:ok, Row.to_domain(row)}
    end
  end

  defp persist_locked(changeset, org, definition) do
    case Repo.insert(changeset,
           on_conflict: :nothing,
           conflict_target: [:mission_id, :derived_definition_id, :version]
         ) do
      {:ok, %Row{id: nil}} -> existing_result(org, definition)
      {:ok, row} -> {:ok, Row.to_domain(row)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp append_locked(org, mission, attrs, expected_version) do
    current =
      scoped(org, mission)
      |> where([d], d.point_id == ^attrs.point_id)
      |> order_by([d], desc: d.version, asc: d.derived_definition_id)
      |> limit(1)
      |> Repo.one()

    if ((current && current.version) || 0) == expected_version and
         (current && current.derived_definition_id) == Map.get(attrs, :expected_definition_id) do
      definition =
        Definition.new(
          Map.merge(attrs, %{
            mission_id: mission,
            derived_definition_id:
              if(current,
                do: current.derived_definition_id,
                else: definition_id(attrs.point_id)
              ),
            version: expected_version + 1
          })
        )

      persist(definition)
    else
      {:error, :derived_definition_version_conflict}
    end
  end

  defp paginate(query, requested, ordering) do
    total = Repo.aggregate(query, :count)
    page = min(requested, max(1, ceil(total / 25)))

    items =
      query
      |> order_by(^ordering)
      |> limit(25)
      |> offset(^((page - 1) * 25))
      |> Repo.all()
      |> Enum.map(&Row.to_domain/1)

    %{items: items, total_count: total, page: page}
  end

  defp live(org, mission),
    do: from(d in subquery(latest(org, mission)), where: is_nil(d.retired_at))

  defp latest(org, mission),
    do:
      scoped(org, mission)
      |> distinct([d], d.derived_definition_id)
      |> order_by([d], asc: d.derived_definition_id, desc: d.version)

  defp scoped(nil, mission), do: from(d in Row, where: d.mission_id == ^mission)

  defp scoped(org, mission),
    do: from(d in Row, where: d.organization_id == ^org and d.mission_id == ^mission)

  defp existing_result(org, definition) do
    with {:ok, stored} <-
           fetch(org, definition.mission_id, definition.derived_definition_id, definition.version) do
      if content(stored) == content(definition),
        do: {:ok, stored},
        else: {:error, :derived_definition_version_conflict}
    end
  end

  # The save trail (who, via which path) isn't content: the same version saved again by someone
  # else, or through another path, is the same version (SaveTrail).
  defp content(%Definition{} = definition),
    do:
      Jason.encode!(
        Map.from_struct(%{definition | metadata: SaveTrail.without(definition.metadata)})
      )

  defp transaction(org, mission, point, operation) do
    <<key::signed-64, _::binary>> =
      :crypto.hash(:sha256, :erlang.term_to_binary({__MODULE__, org, mission, point}))

    case Repo.transaction(fn ->
           SQL.query!(Repo, "SELECT pg_advisory_xact_lock($1::bigint)", [key])

           finish_operation(operation.())
         end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp finish_operation({:error, reason}), do: Repo.rollback(reason)
  defp finish_operation(result), do: result

  defp definition_id(point) do
    digest = :crypto.hash(:sha256, point) |> Base.url_encode64(padding: false)
    "derived_definition:#{binary_part(digest, 0, 16)}"
  end
end
