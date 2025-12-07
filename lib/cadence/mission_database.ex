defmodule Cadence.MissionDatabase do
  @moduledoc """
  Context for the Mission Database - unified C&T definitions catalog.

  Provides a unified search interface across:
  - Parameters (telemetry items from DefinitionSet)
  - MetaCommands (command definitions from DefinitionSet)
  - DerivedItems (mission-scoped computed values)

  ## Database Catalog Model

  Databases are mission-scoped catalog entries that contain versioned DefinitionSets.
  Targets reference specific DefinitionSet versions (required).

      Mission
      └── Databases (the "Catalog"):
          ├── "york-transport"
          │   ├── v1.0.0 → DefinitionSet
          │   └── v1.4.0 → DefinitionSet
          └── "lockheed-transport"
              └── v2.1.0 → DefinitionSet

      Targets:
          ├── YORK-001 → references york-transport v1.4.0
          └── LM-001   → references lockheed-transport v2.1.0
  """

  import Ecto.Query
  alias Cadence.Repo

  alias Cadence.MissionDatabase.{
    Database,
    DefinitionSet,
    Container,
    ContainerEntry,
    Parameter,
    MetaCommand
  }

  alias Cadence.Telemetry.Database.DerivedItem

  # ===========================================================================
  # Database Catalog
  # ===========================================================================

  @doc """
  Lists all databases for a mission (the catalog).
  """
  def list_databases(mission_id) do
    Database.list_for_mission(mission_id)
  end

  @doc """
  Lists all databases for a mission with version counts and latest version info.
  """
  def list_databases_with_stats(mission_id) do
    databases = Database.list_for_mission(mission_id)

    Enum.map(databases, fn db ->
      db = Database.with_definition_sets(db)
      latest = Database.latest_published(db)

      %{
        database: db,
        version_count: length(db.definition_sets),
        latest_version: latest && latest.version,
        latest_published_at: latest && latest.published_at
      }
    end)
  end

  @doc """
  Gets a database by ID.
  """
  def get_database(id) do
    Database.get(id)
  end

  @doc """
  Gets a database by mission and slug.
  """
  def get_database_by_slug(mission_id, slug) do
    Database.get_by_slug(mission_id, slug)
  end

  @doc """
  Creates a new database in the catalog.
  """
  def create_database(attrs) do
    Database.create(attrs)
  end

  @doc """
  Updates a database.
  """
  def update_database(database, attrs) do
    Database.update(database, attrs)
  end

  @doc """
  Deletes a database and all its definition sets.
  """
  def delete_database(database) do
    Database.delete(database)
  end

  # ===========================================================================
  # DefinitionSet Management
  # ===========================================================================

  @doc """
  Gets a DefinitionSet by ID.
  """
  def get_definition_set(id) do
    DefinitionSet.get(id)
  end

  @doc """
  Lists all DefinitionSets for a database.
  """
  def list_definition_sets(database_id) do
    DefinitionSet.list_for_database(database_id)
  end

  @doc """
  Gets the latest published DefinitionSet for a database.
  """
  def get_latest_definition_set(database_id) do
    DefinitionSet.get_latest_published(database_id)
  end

  @doc """
  Gets telemetry catalog data for widget configuration.

  Returns packets (containers) and derived items for the mission.
  Uses the first available database's latest published version.
  """
  def get_telemetry_catalog(mission_id) do
    databases = list_databases(mission_id)

    # Find first database with a published definition set
    definition_set =
      Enum.find_value(databases, fn db ->
        get_latest_definition_set(db.id)
      end)

    case definition_set do
      nil ->
        {:error, :no_active_database}

      ds ->
        packets = list_containers_for_catalog(ds.id)
        derived_items = DerivedItem.list_all(mission_id)
        {:ok, %{packets: packets, derived_items: derived_items}}
    end
  end

  defp list_containers_for_catalog(definition_set_id) do
    containers =
      from(c in Container,
        where: c.definition_set_id == ^definition_set_id,
        where: c.abstract == false or is_nil(c.abstract),
        order_by: [asc: c.name],
        preload: [
          container_entries:
            ^from(e in ContainerEntry,
              order_by: e.display_order,
              preload: [parameter: :data_type]
            )
        ]
      )
      |> Repo.all()

    # Transform to catalog format expected by UI
    Enum.map(containers, fn container ->
      items =
        container.container_entries
        |> Enum.filter(fn entry -> entry.parameter != nil end)
        |> Enum.map(fn entry ->
          param = entry.parameter
          unit = get_unit_from_data_type(param.data_type)

          %{
            name: param.name,
            description: param.description,
            units: unit
          }
        end)

      %{
        id: container.id,
        name: container.name,
        description: container.description,
        items: items
      }
    end)
  end

  defp get_unit_from_data_type(nil), do: nil

  defp get_unit_from_data_type(data_type) do
    case data_type.unit do
      %{symbol: symbol} when is_binary(symbol) and symbol != "" -> symbol
      %{name: name} when is_binary(name) and name != "" -> name
      _ -> nil
    end
  end

  @doc """
  Gets DefinitionSet stats for display.
  """
  def get_definition_set_with_stats(definition_set_id) do
    case DefinitionSet.get(definition_set_id) do
      nil ->
        nil

      definition_set ->
        %{
          definition_set: definition_set,
          container_count: count_containers(definition_set_id),
          parameter_count: count_parameters(definition_set_id),
          command_count: count_commands(definition_set_id)
        }
    end
  end

  # ===========================================================================
  # Catalog Search
  # ===========================================================================

  @doc """
  Searches the catalog across all item types.

  Returns a map with:
  - `:items` - List of catalog items (unified format)
  - `:total_count` - Total matching items
  - `:has_more` - Whether more results exist

  ## Options

  - `:type` - Filter by type: `:all`, `:telemetry`, `:commands`, `:derived`
  - `:limit` - Max results to return (default: 50)
  - `:offset` - Number of results to skip (default: 0)

  ## Example

      search_catalog(def_set_id, mission_id, "CPU", type: :telemetry, limit: 20)
  """
  def search_catalog(definition_set_id, mission_id, query, opts \\ []) do
    type_filter = Keyword.get(opts, :type, :all)
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    {items, total_count} =
      case type_filter do
        :telemetry ->
          search_parameters(definition_set_id, query, limit, offset)

        :commands ->
          search_commands(definition_set_id, query, limit, offset)

        :derived ->
          search_derived(mission_id, query, limit, offset)

        :all ->
          search_all(definition_set_id, mission_id, query, limit, offset)
      end

    %{
      items: items,
      total_count: total_count,
      has_more: offset + length(items) < total_count
    }
  end

  @doc """
  Gets detailed information for a specific catalog item.
  """
  def get_item_details(:telemetry, parameter_id) do
    Parameter
    |> Repo.get(parameter_id)
    |> Repo.preload([:data_type])
    |> case do
      nil -> nil
      param -> build_parameter_details(param)
    end
  end

  def get_item_details(:command, command_id) do
    MetaCommand
    |> Repo.get(command_id)
    |> Repo.preload([:arguments])
    |> case do
      nil -> nil
      cmd -> build_command_details(cmd)
    end
  end

  def get_item_details(:derived, derived_id) do
    DerivedItem
    |> Repo.get(derived_id)
    |> case do
      nil -> nil
      item -> build_derived_details(item)
    end
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  defp count_containers(definition_set_id) do
    from(c in Container,
      where: c.definition_set_id == ^definition_set_id,
      where: c.abstract == false or is_nil(c.abstract),
      select: count(c.id)
    )
    |> Repo.one()
  end

  defp count_parameters(definition_set_id) do
    from(p in Parameter,
      where: p.definition_set_id == ^definition_set_id,
      select: count(p.id)
    )
    |> Repo.one()
  end

  defp count_commands(definition_set_id) do
    from(c in MetaCommand,
      where: c.definition_set_id == ^definition_set_id,
      where: c.abstract == false or is_nil(c.abstract),
      select: count(c.id)
    )
    |> Repo.one()
  end

  defp search_parameters(nil, _query, _limit, _offset), do: {[], 0}

  defp search_parameters(definition_set_id, query, limit, offset) do
    base_filter =
      from(p in Parameter,
        left_join: ce in ContainerEntry,
        on: ce.parameter_id == p.id,
        left_join: c in Container,
        on: ce.container_id == c.id,
        where: p.definition_set_id == ^definition_set_id
      )

    filtered_query =
      if query && query != "" do
        search_term = "%#{String.downcase(query)}%"

        from([p, _ce, c] in base_filter,
          where:
            ilike(p.name, ^search_term) or
              ilike(p.description, ^search_term) or
              ilike(c.name, ^search_term)
        )
      else
        base_filter
      end

    total =
      from([p, _ce, _c] in filtered_query, select: p.id)
      |> Repo.aggregate(:count)

    items =
      from([p, _ce, c] in filtered_query,
        order_by: [asc: c.name, asc: p.name],
        limit: ^limit,
        offset: ^offset,
        select: %{parameter: p, container_name: c.name}
      )
      |> Repo.all()
      |> Enum.map(fn %{parameter: p, container_name: container_name} ->
        p = Repo.preload(p, data_type: :unit)
        build_catalog_item(:telemetry, p, container_name)
      end)

    {items, total}
  end

  defp search_commands(nil, _query, _limit, _offset), do: {[], 0}

  defp search_commands(definition_set_id, query, limit, offset) do
    base_filter =
      from(c in MetaCommand,
        where: c.definition_set_id == ^definition_set_id,
        where: c.abstract == false or is_nil(c.abstract)
      )

    filtered_query =
      if query && query != "" do
        search_term = "%#{String.downcase(query)}%"

        from(c in base_filter,
          where:
            ilike(c.name, ^search_term) or
              ilike(c.description, ^search_term)
        )
      else
        base_filter
      end

    total =
      from(c in filtered_query, select: c.id)
      |> Repo.aggregate(:count)

    items =
      filtered_query
      |> order_by([c], asc: c.name)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()
      |> Repo.preload(:arguments)
      |> Enum.map(&build_catalog_item(:command, &1, nil))

    {items, total}
  end

  defp search_derived(mission_id, query, limit, offset) do
    base_filter =
      from(d in DerivedItem,
        where: d.mission_id == ^mission_id
      )

    filtered_query =
      if query && query != "" do
        search_term = "%#{String.downcase(query)}%"

        from(d in base_filter,
          where:
            ilike(d.name, ^search_term) or
              ilike(d.description, ^search_term) or
              ilike(d.expression, ^search_term)
        )
      else
        base_filter
      end

    total =
      from(d in filtered_query, select: d.id)
      |> Repo.aggregate(:count)

    items =
      filtered_query
      |> order_by([d], asc: d.name)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()
      |> Enum.map(&build_catalog_item(:derived, &1, nil))

    {items, total}
  end

  defp search_all(definition_set_id, mission_id, query, limit, offset) do
    {param_items, param_total} = search_parameters(definition_set_id, query, limit, 0)
    {cmd_items, cmd_total} = search_commands(definition_set_id, query, limit, 0)
    {derived_items, derived_total} = search_derived(mission_id, query, limit, 0)

    total = param_total + cmd_total + derived_total

    all_items =
      (param_items ++ cmd_items ++ derived_items)
      |> Enum.sort_by(& &1.name)

    items =
      all_items
      |> Enum.drop(offset)
      |> Enum.take(limit)

    {items, total}
  end

  defp build_catalog_item(:telemetry, parameter, container_name) do
    qualified_name =
      if container_name do
        "#{container_name}.#{parameter.name}"
      else
        parameter.name
      end

    %{
      id: parameter.id,
      type: :telemetry,
      name: qualified_name,
      short_name: parameter.name,
      container_name: container_name,
      description: parameter.description || parameter.short_description,
      data_type: get_data_type_display(parameter.data_type),
      units: get_units_display(parameter.data_type),
      metadata: %{
        parameter_source: parameter.parameter_source,
        significance: parameter.significance,
        stale_timeout_ms: parameter.stale_timeout_ms
      }
    }
  end

  defp build_catalog_item(:command, command, _) do
    %{
      id: command.id,
      type: :command,
      name: command.name,
      short_name: command.name,
      container_name: nil,
      description: command.description || command.short_description,
      data_type: nil,
      units: nil,
      metadata: %{
        opcode: command.opcode,
        is_hazardous: command.is_hazardous,
        hazard_description: command.hazard_description,
        significance: command.significance,
        argument_count: length(command.arguments || []),
        arguments:
          Enum.map(command.arguments || [], fn arg ->
            %{
              name: arg.name,
              data_type_ref: arg.data_type_ref,
              required: arg.required,
              default_value: arg.default_value
            }
          end)
      }
    }
  end

  defp build_catalog_item(:derived, derived, _) do
    %{
      id: derived.id,
      type: :derived,
      name: derived.name,
      short_name: derived.name,
      container_name: nil,
      description: derived.description,
      data_type: derived.data_type,
      units: derived.units,
      metadata: %{
        expression: derived.expression,
        source_items: derived.source_items,
        enabled: derived.enabled
      }
    }
  end

  defp build_parameter_details(parameter) do
    %{
      type: :telemetry,
      parameter: parameter,
      data_type: parameter.data_type
    }
  end

  defp build_command_details(command) do
    %{
      type: :command,
      command: command,
      arguments: command.arguments
    }
  end

  defp build_derived_details(derived) do
    %{
      type: :derived,
      derived_item: derived
    }
  end

  defp get_data_type_display(nil), do: nil

  defp get_data_type_display(data_type) do
    data_type.base_type || data_type.name
  end

  defp get_units_display(nil), do: nil

  defp get_units_display(data_type) do
    case data_type.unit do
      nil -> nil
      unit -> unit.symbol || unit.name
    end
  end
end
