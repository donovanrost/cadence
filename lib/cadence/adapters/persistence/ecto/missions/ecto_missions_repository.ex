defmodule Cadence.Adapters.Persistence.Ecto.Missions.EctoMissionsRepository do
  @moduledoc """
  Ecto-based implementation of the MissionsRepository port.

  This adapter converts between domain entities and Ecto schemas,
  providing persistence for missions and mission memberships using PostgreSQL.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :missions_repository, Cadence.Adapters.Persistence.Ecto.Missions.EctoMissionsRepository

  Then accessed via:

      repo = Cadence.Ports.Repository.Missions.MissionsRepository.impl()
      {:ok, mission} = repo.find(mission_id)
  """

  @behaviour Cadence.Ports.Repository.Missions.MissionsRepository

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Missions.Mission, as: MissionSchema
  alias Cadence.Missions.MissionMembership, as: MembershipSchema
  alias Cadence.Domain.Missions.Entities.Mission, as: MissionEntity
  alias Cadence.Domain.Missions.Entities.MissionMembership, as: MembershipEntity

  # ===========================================================================
  # Mission Operations
  # ===========================================================================

  @impl true
  def find(id) do
    case Repo.get(MissionSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity(schema)}
    end
  end

  @impl true
  def find_by_org(id, organization_id) do
    query =
      from m in MissionSchema,
        where: m.id == ^id and m.organization_id == ^organization_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity(schema)}
    end
  end

  @impl true
  def list(organization_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    phase = Keyword.get(opts, :phase)
    limit = Keyword.get(opts, :limit)

    query =
      from m in MissionSchema,
        where: m.organization_id == ^organization_id,
        order_by: [desc: m.inserted_at]

    query =
      query
      |> apply_filter(:status, status)
      |> apply_filter(:phase, phase)
      |> apply_limit(limit)

    query
    |> Repo.all()
    |> Enum.map(&schema_to_entity/1)
  end

  @impl true
  def save(%MissionEntity{id: nil} = entity) do
    attrs = entity_to_schema_attrs(entity)

    %MissionSchema{}
    |> MissionSchema.changeset(attrs)
    |> Repo.insert()
    |> handle_result()
  end

  def save(%MissionEntity{id: id} = entity) do
    case Repo.get(MissionSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> MissionSchema.update_changeset(entity_to_schema_attrs(entity))
        |> Repo.update()
        |> handle_result()
    end
  end

  @impl true
  def delete(id) do
    case Repo.get(MissionSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        case Repo.delete(schema) do
          {:ok, deleted} -> {:ok, schema_to_entity(deleted)}
          {:error, _changeset} -> {:error, :delete_failed}
        end
    end
  end

  # ===========================================================================
  # Mission Membership Operations
  # ===========================================================================

  @impl true
  def find_membership(id) do
    case Repo.get(MembershipSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, membership_schema_to_entity(schema)}
    end
  end

  @impl true
  def list_memberships(mission_id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [:user])

    query =
      from mm in MembershipSchema,
        where: mm.mission_id == ^mission_id

    query
    |> preload(^preloads)
    |> Repo.all()
    |> Enum.map(&membership_schema_to_entity/1)
  end

  @impl true
  def save_membership(%MembershipEntity{id: nil} = entity) do
    attrs = membership_entity_to_schema_attrs(entity)

    %MembershipSchema{}
    |> MembershipSchema.changeset(attrs)
    |> Repo.insert()
    |> handle_membership_result()
  end

  def save_membership(%MembershipEntity{id: id} = entity) do
    case Repo.get(MembershipSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> MembershipSchema.changeset(membership_entity_to_schema_attrs(entity))
        |> Repo.update()
        |> handle_membership_result()
    end
  end

  @impl true
  def delete_membership(id) do
    case Repo.get(MembershipSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        case Repo.delete(schema) do
          {:ok, deleted} -> {:ok, membership_schema_to_entity(deleted)}
          {:error, _changeset} -> {:error, :delete_failed}
        end
    end
  end

  @impl true
  def find_user_role(user_id, mission_id) do
    query =
      from mm in MembershipSchema,
        where: mm.user_id == ^user_id and mm.mission_id == ^mission_id,
        select: mm.role

    case Repo.one(query) do
      nil -> {:error, :not_found}
      role -> {:ok, parse_role(role)}
    end
  end

  # ===========================================================================
  # Mission Entity <-> Schema Conversion
  # ===========================================================================

  @doc """
  Converts an Ecto mission schema to a domain entity.
  """
  @spec schema_to_entity(MissionSchema.t()) :: MissionEntity.t()
  def schema_to_entity(%MissionSchema{} = schema) do
    %MissionEntity{
      id: schema.id,
      organization_id: schema.organization_id,
      name: schema.name,
      slug: schema.slug,
      description: schema.description,
      status: parse_status(schema.status),
      phase: parse_phase(schema.phase),
      config: schema.config || %{},
      metadata: schema.metadata || %{},
      config_generation: schema.config_generation || 1,
      start_date: schema.start_date,
      end_date: schema.end_date,
      created_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  @doc """
  Converts a domain mission entity to schema attributes for persistence.
  """
  @spec entity_to_schema_attrs(MissionEntity.t()) :: map()
  def entity_to_schema_attrs(%MissionEntity{} = entity) do
    %{
      organization_id: entity.organization_id,
      name: entity.name,
      slug: entity.slug,
      description: entity.description,
      status: atom_to_string(entity.status),
      phase: atom_to_string(entity.phase),
      config: entity.config,
      metadata: entity.metadata,
      start_date: entity.start_date,
      end_date: entity.end_date
    }
  end

  # ===========================================================================
  # Membership Entity <-> Schema Conversion
  # ===========================================================================

  @doc """
  Converts an Ecto membership schema to a domain entity.
  """
  @spec membership_schema_to_entity(MembershipSchema.t()) :: MembershipEntity.t()
  def membership_schema_to_entity(%MembershipSchema{} = schema) do
    %MembershipEntity{
      id: schema.id,
      user_id: schema.user_id,
      mission_id: schema.mission_id,
      role: parse_role(schema.role),
      created_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  @doc """
  Converts a domain membership entity to schema attributes for persistence.
  """
  @spec membership_entity_to_schema_attrs(MembershipEntity.t()) :: map()
  def membership_entity_to_schema_attrs(%MembershipEntity{} = entity) do
    %{
      user_id: entity.user_id,
      mission_id: entity.mission_id,
      role: atom_to_string(entity.role)
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp handle_result({:ok, schema}), do: {:ok, schema_to_entity(schema)}
  defp handle_result({:error, changeset}), do: {:error, extract_errors(changeset)}

  defp handle_membership_result({:ok, schema}), do: {:ok, membership_schema_to_entity(schema)}
  defp handle_membership_result({:error, changeset}), do: {:error, extract_errors(changeset)}

  defp extract_errors(%Ecto.Changeset{} = changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    {:validation, errors}
  end

  defp apply_filter(query, _field, nil), do: query

  defp apply_filter(query, :status, status) when is_atom(status) do
    status_string = Atom.to_string(status)
    from m in query, where: m.status == ^status_string
  end

  defp apply_filter(query, :phase, phase) when is_atom(phase) do
    phase_string = Atom.to_string(phase)
    from m in query, where: m.phase == ^phase_string
  end

  defp apply_filter(query, field, value) when is_binary(value) do
    from m in query, where: field(m, ^field) == ^value
  end

  defp apply_limit(query, nil), do: query
  defp apply_limit(query, limit), do: from(m in query, limit: ^limit)

  defp parse_status(status) when is_binary(status) do
    case status do
      "inactive" -> :inactive
      "active" -> :active
      "suspended" -> :suspended
      _ -> :inactive
    end
  end

  defp parse_status(status) when is_atom(status), do: status

  defp parse_phase(phase) when is_binary(phase) do
    case phase do
      "planning" -> :planning
      "testing" -> :testing
      "operational" -> :operational
      "decommissioned" -> :decommissioned
      _ -> :planning
    end
  end

  defp parse_phase(phase) when is_atom(phase), do: phase

  defp parse_role(role) when is_binary(role) do
    case role do
      "viewer" -> :viewer
      "operator" -> :operator
      "engineer" -> :engineer
      "admin" -> :admin
      _ -> :viewer
    end
  end

  defp parse_role(role) when is_atom(role), do: role

  defp atom_to_string(nil), do: nil
  defp atom_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp atom_to_string(string) when is_binary(string), do: string
end
