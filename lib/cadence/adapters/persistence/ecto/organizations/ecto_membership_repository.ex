defmodule Cadence.Adapters.Persistence.Ecto.Organizations.EctoMembershipRepository do
  @moduledoc """
  Ecto-based implementation of the MembershipRepository port.

  This adapter converts between domain entities and Ecto schemas,
  providing persistence for organization memberships using PostgreSQL.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :membership_repository, Cadence.Adapters.Persistence.Ecto.Organizations.EctoMembershipRepository

  Then accessed via:

      repo = Cadence.Ports.Repository.Organizations.MembershipRepository.impl()
      {:ok, membership} = repo.find(id)
  """

  @behaviour Cadence.Ports.Repository.Organizations.MembershipRepository

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Organizations.OrganizationMembership, as: MembershipSchema
  alias Cadence.Domain.Organizations.Entities.OrganizationMembership, as: MembershipEntity

  # ===========================================================================
  # Membership CRUD Operations
  # ===========================================================================

  @impl true
  def find(id) do
    case Repo.get(MembershipSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity(schema)}
    end
  end

  @impl true
  def find_by_user_and_org(user_id, organization_id) do
    query =
      from m in MembershipSchema,
        where: m.user_id == ^user_id and m.organization_id == ^organization_id

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity(schema)}
    end
  end

  @impl true
  def save(%MembershipEntity{id: nil} = entity) do
    attrs = entity_to_schema_attrs(entity)

    %MembershipSchema{}
    |> MembershipSchema.changeset(attrs)
    |> Repo.insert()
    |> handle_result()
  end

  def save(%MembershipEntity{id: id} = entity) do
    case Repo.get(MembershipSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> MembershipSchema.changeset(entity_to_schema_attrs(entity))
        |> Repo.update()
        |> handle_result()
    end
  end

  @impl true
  def list_for_organization(organization_id, opts \\ []) do
    role = Keyword.get(opts, :role)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    preloads = Keyword.get(opts, :preload, [])

    query =
      from m in MembershipSchema,
        where: m.organization_id == ^organization_id,
        order_by: [asc: m.inserted_at],
        limit: ^limit,
        offset: ^offset

    query = apply_role_filter(query, role)

    query
    |> preload(^preloads)
    |> Repo.all()
    |> Enum.map(&schema_to_entity/1)
  end

  @impl true
  def list_for_user(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    preloads = Keyword.get(opts, :preload, [])

    query =
      from m in MembershipSchema,
        where: m.user_id == ^user_id,
        order_by: [asc: m.inserted_at],
        limit: ^limit,
        offset: ^offset

    query
    |> preload(^preloads)
    |> Repo.all()
    |> Enum.map(&schema_to_entity/1)
  end

  @impl true
  def delete(id) do
    case Repo.get(MembershipSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        case Repo.delete(schema) do
          {:ok, deleted} -> {:ok, schema_to_entity(deleted)}
          {:error, _changeset} -> {:error, :delete_failed}
        end
    end
  end

  @impl true
  def delete_all_for_user(user_id) do
    query =
      from m in MembershipSchema,
        where: m.user_id == ^user_id

    Repo.delete_all(query)
    :ok
  end

  @impl true
  def delete_all_for_organization(organization_id) do
    query =
      from m in MembershipSchema,
        where: m.organization_id == ^organization_id

    Repo.delete_all(query)
    :ok
  end

  # ===========================================================================
  # Query Operations
  # ===========================================================================

  @impl true
  def exists?(user_id, organization_id) do
    query =
      from m in MembershipSchema,
        where: m.user_id == ^user_id and m.organization_id == ^organization_id,
        select: count(m.id)

    Repo.one(query) > 0
  end

  @impl true
  def count_for_organization(organization_id) do
    query =
      from m in MembershipSchema,
        where: m.organization_id == ^organization_id,
        select: count(m.id)

    Repo.one(query) || 0
  end

  @impl true
  def count_owners(organization_id) do
    query =
      from m in MembershipSchema,
        where: m.organization_id == ^organization_id and m.role == "owner",
        select: count(m.id)

    Repo.one(query) || 0
  end

  # ===========================================================================
  # Entity <-> Schema Conversion
  # ===========================================================================

  @doc """
  Converts an Ecto schema to a domain entity.
  """
  @spec schema_to_entity(MembershipSchema.t()) :: MembershipEntity.t()
  def schema_to_entity(%MembershipSchema{} = schema) do
    role = parse_role(schema.role)

    %MembershipEntity{
      id: schema.id,
      user_id: schema.user_id,
      organization_id: schema.organization_id,
      role: role,
      created_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  @doc """
  Converts a domain entity to schema attributes for persistence.
  """
  @spec entity_to_schema_attrs(MembershipEntity.t()) :: map()
  def entity_to_schema_attrs(%MembershipEntity{} = entity) do
    %{
      user_id: entity.user_id,
      organization_id: entity.organization_id,
      role: Atom.to_string(entity.role)
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp handle_result({:ok, schema}), do: {:ok, schema_to_entity(schema)}
  defp handle_result({:error, changeset}), do: {:error, extract_errors(changeset)}

  defp extract_errors(%Ecto.Changeset{} = changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    {:validation, errors}
  end

  defp apply_role_filter(query, nil), do: query

  defp apply_role_filter(query, role) when is_atom(role) do
    role_string = Atom.to_string(role)
    from m in query, where: m.role == ^role_string
  end

  defp apply_role_filter(query, role) when is_binary(role) do
    from m in query, where: m.role == ^role
  end

  defp parse_role(role) when is_binary(role) do
    case role do
      "owner" -> :owner
      "admin" -> :admin
      "member" -> :member
      _ -> :member
    end
  end

  defp parse_role(role) when is_atom(role), do: role
end
