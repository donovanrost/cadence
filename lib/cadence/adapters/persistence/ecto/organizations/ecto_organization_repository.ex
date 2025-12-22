defmodule Cadence.Adapters.Persistence.Ecto.Organizations.EctoOrganizationRepository do
  @moduledoc """
  Ecto-based implementation of the OrganizationRepository port.

  This adapter converts between domain entities and Ecto schemas,
  providing persistence for organizations using PostgreSQL.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :organization_repository, Cadence.Adapters.Persistence.Ecto.Organizations.EctoOrganizationRepository

  Then accessed via:

      repo = Cadence.Ports.Repository.Organizations.OrganizationRepository.impl()
      {:ok, org} = repo.find(id)
  """

  @behaviour Cadence.Ports.Repository.Organizations.OrganizationRepository

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Organizations.Organization, as: OrganizationSchema
  alias Cadence.Domain.Organizations.Entities.Organization, as: OrganizationEntity
  alias Cadence.Domain.Organizations.ValueObjects.Quotas

  # ===========================================================================
  # Organization CRUD Operations
  # ===========================================================================

  @impl true
  def find(id) do
    case Repo.get(OrganizationSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity(schema)}
    end
  end

  @impl true
  def find_by_slug(slug) do
    case Repo.get_by(OrganizationSchema, slug: slug) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity(schema)}
    end
  end

  @impl true
  def save(%OrganizationEntity{id: nil} = entity) do
    attrs = entity_to_schema_attrs(entity)

    %OrganizationSchema{}
    |> OrganizationSchema.changeset(attrs)
    |> Repo.insert()
    |> handle_result()
  end

  def save(%OrganizationEntity{id: id} = entity) do
    case Repo.get(OrganizationSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        |> OrganizationSchema.update_changeset(entity_to_schema_attrs(entity))
        |> Repo.update()
        |> handle_result()
    end
  end

  @impl true
  def list(opts \\ []) do
    status = Keyword.get(opts, :status)
    tier = Keyword.get(opts, :tier)
    search = Keyword.get(opts, :search)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from o in OrganizationSchema,
        order_by: [desc: o.inserted_at],
        limit: ^limit,
        offset: ^offset

    query =
      query
      |> apply_filter(:status, status)
      |> apply_filter(:subscription_tier, tier)
      |> apply_search_filter(search)

    query
    |> Repo.all()
    |> Enum.map(&schema_to_entity/1)
  end

  @impl true
  def delete(id) do
    case Repo.get(OrganizationSchema, id) do
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
  # Counting Operations
  # ===========================================================================

  @impl true
  def count_missions(org_id) do
    query =
      from m in Cadence.Missions.Mission,
        where: m.organization_id == ^org_id,
        select: count(m.id)

    Repo.one(query) || 0
  end

  @impl true
  def count_mission_targets(mission_id) do
    query =
      from t in Cadence.Targets.Target,
        where: t.mission_id == ^mission_id,
        select: count(t.id)

    Repo.one(query) || 0
  end

  @impl true
  def count_users(org_id) do
    query =
      from u in Cadence.Accounts.User,
        where: u.organization_id == ^org_id,
        select: count(u.id)

    Repo.one(query) || 0
  end

  @impl true
  def count_memberships(org_id) do
    query =
      from m in Cadence.Organizations.OrganizationMembership,
        where: m.organization_id == ^org_id,
        select: count(m.id)

    Repo.one(query) || 0
  end

  # ===========================================================================
  # Entity <-> Schema Conversion
  # ===========================================================================

  @doc """
  Converts an Ecto schema to a domain entity.
  """
  @spec schema_to_entity(OrganizationSchema.t()) :: OrganizationEntity.t()
  def schema_to_entity(%OrganizationSchema{} = schema) do
    # Parse status and tier from strings to atoms
    status = parse_status(schema.status)
    tier = parse_tier(schema.subscription_tier)

    # Build quotas from schema fields
    quotas = Quotas.from_map(%{
      max_missions: schema.max_missions,
      max_targets_per_mission: schema.max_targets_per_mission,
      max_users: schema.max_users,
      storage_quota_gb: schema.storage_quota_gb
    })

    %OrganizationEntity{
      id: schema.id,
      name: schema.name,
      slug: schema.slug,
      status: status,
      subscription_tier: tier,
      quotas: quotas,
      settings: schema.settings || %{},
      metadata: schema.metadata || %{},
      created_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  @doc """
  Converts a domain entity to schema attributes for persistence.
  """
  @spec entity_to_schema_attrs(OrganizationEntity.t()) :: map()
  def entity_to_schema_attrs(%OrganizationEntity{} = entity) do
    quotas_map = Quotas.to_map(entity.quotas)

    %{
      name: entity.name,
      slug: entity.slug,
      status: Atom.to_string(entity.status),
      subscription_tier: Atom.to_string(entity.subscription_tier),
      max_missions: quotas_map.max_missions,
      max_targets_per_mission: quotas_map.max_targets_per_mission,
      max_users: quotas_map.max_users,
      storage_quota_gb: quotas_map.storage_quota_gb,
      settings: entity.settings,
      metadata: entity.metadata
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

  defp apply_filter(query, _field, nil), do: query

  defp apply_filter(query, :status, status) when is_atom(status) do
    status_string = Atom.to_string(status)
    from o in query, where: o.status == ^status_string
  end

  defp apply_filter(query, :subscription_tier, tier) when is_atom(tier) do
    tier_string = Atom.to_string(tier)
    from o in query, where: o.subscription_tier == ^tier_string
  end

  defp apply_filter(query, field, value) do
    from o in query, where: field(o, ^field) == ^value
  end

  defp apply_search_filter(query, nil), do: query

  defp apply_search_filter(query, search) when search != "" do
    search_term = "%#{search}%"
    from o in query, where: ilike(o.name, ^search_term) or ilike(o.slug, ^search_term)
  end

  defp apply_search_filter(query, _), do: query

  defp parse_status(status) when is_binary(status) do
    case status do
      "active" -> :active
      "suspended" -> :suspended
      "terminated" -> :terminated
      _ -> :active
    end
  end

  defp parse_status(status) when is_atom(status), do: status

  defp parse_tier(tier) when is_binary(tier) do
    case tier do
      "free" -> :free
      "pro" -> :pro
      "enterprise" -> :enterprise
      _ -> :free
    end
  end

  defp parse_tier(tier) when is_atom(tier), do: tier
end
