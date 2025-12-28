defmodule Cadence.Adapters.Persistence.Ecto.Accounts.EctoUserRepository do
  @moduledoc """
  Ecto-based implementation of the UserRepository port.

  This adapter converts between domain entities and Ecto schemas,
  providing persistence for users using PostgreSQL.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :user_repository, Cadence.Adapters.Persistence.Ecto.Accounts.EctoUserRepository

  Then accessed via:

      repo = Cadence.Ports.Repository.Accounts.UserRepository.impl()
      {:ok, user} = repo.find(id)
  """

  @behaviour Cadence.Ports.Repository.Accounts.UserRepository

  import Ecto.Query

  alias Cadence.Accounts.User, as: UserSchema
  alias Cadence.Domain.Accounts.Entities.User, as: UserEntity
  alias Cadence.Repo

  # ===========================================================================
  # User CRUD Operations
  # ===========================================================================

  @impl true
  def find(id) do
    case Repo.get(UserSchema, id) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity(schema)}
    end
  end

  @impl true
  def find_by_email(email) do
    email_lower = String.downcase(email)

    case Repo.get_by(UserSchema, email: email_lower) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity(schema)}
    end
  end

  @impl true
  def save(%UserEntity{id: nil} = entity) do
    attrs = entity_to_schema_attrs(entity)

    %UserSchema{}
    |> UserSchema.email_changeset(attrs)
    |> maybe_apply_password(entity)
    |> Repo.insert()
    |> handle_result()
  end

  def save(%UserEntity{id: id} = entity) do
    case Repo.get(UserSchema, id) do
      nil ->
        {:error, :not_found}

      schema ->
        schema
        # Use validate_unique: false to skip the "email did not change" validation
        # This allows us to update other fields without requiring an email change
        |> UserSchema.email_changeset(entity_to_schema_attrs(entity), validate_unique: false)
        |> maybe_apply_password_update(schema, entity)
        |> maybe_apply_confirmed_at(entity)
        |> Repo.update()
        |> handle_result()
    end
  end

  @impl true
  def list(opts \\ []) do
    org_id = Keyword.get(opts, :organization_id)
    role = Keyword.get(opts, :role)
    system_admin = Keyword.get(opts, :system_admin)
    confirmed = Keyword.get(opts, :confirmed)
    search = Keyword.get(opts, :search)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from u in UserSchema,
        order_by: [desc: u.inserted_at],
        limit: ^limit,
        offset: ^offset

    query =
      query
      |> apply_filter(:organization_id, org_id)
      |> apply_filter(:role, role)
      |> apply_filter(:system_admin, system_admin)
      |> apply_confirmed_filter(confirmed)
      |> apply_search_filter(search)

    query
    |> Repo.all()
    |> Enum.map(&schema_to_entity/1)
  end

  @impl true
  def delete(id) do
    case Repo.get(UserSchema, id) do
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
  # Organization-scoped Operations
  # ===========================================================================

  @impl true
  def list_for_organization(org_id, opts \\ []) do
    list(Keyword.put(opts, :organization_id, org_id))
  end

  @impl true
  def count_for_organization(org_id) do
    query =
      from u in UserSchema,
        where: u.organization_id == ^org_id,
        select: count(u.id)

    Repo.one(query) || 0
  end

  @impl true
  def find_by_email_in_organization(org_id, email) do
    email_lower = String.downcase(email)

    query =
      from u in UserSchema,
        where: u.organization_id == ^org_id,
        where: u.email == ^email_lower

    case Repo.one(query) do
      nil -> {:error, :not_found}
      schema -> {:ok, schema_to_entity(schema)}
    end
  end

  # ===========================================================================
  # Email Uniqueness
  # ===========================================================================

  @impl true
  def email_taken?(email, exclude_user_id \\ nil) do
    email_lower = String.downcase(email)

    query =
      from u in UserSchema,
        where: u.email == ^email_lower

    query =
      if exclude_user_id do
        from u in query, where: u.id != ^exclude_user_id
      else
        query
      end

    Repo.exists?(query)
  end

  # ===========================================================================
  # Entity <-> Schema Conversion
  # ===========================================================================

  @doc """
  Converts an Ecto schema to a domain entity.
  """
  @spec schema_to_entity(UserSchema.t()) :: UserEntity.t()
  def schema_to_entity(%UserSchema{} = schema) do
    role = parse_role(schema.role)

    %UserEntity{
      id: schema.id,
      email: schema.email,
      hashed_password: schema.hashed_password,
      confirmed_at: schema.confirmed_at,
      role: role,
      system_admin: schema.system_admin || false,
      organization_id: nil,
      created_at: schema.inserted_at,
      updated_at: schema.updated_at
    }
  end

  @doc """
  Converts a domain entity to schema attributes for persistence.
  """
  @spec entity_to_schema_attrs(UserEntity.t()) :: map()
  def entity_to_schema_attrs(%UserEntity{} = entity) do
    %{
      email: entity.email,
      role: Atom.to_string(entity.role),
      system_admin: entity.system_admin,
      confirmed_at: entity.confirmed_at
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

    # Check for email uniqueness violation
    if Map.has_key?(errors, :email) && "has already been taken" in Map.get(errors, :email, []) do
      :email_already_taken
    else
      {:validation, errors}
    end
  end

  defp maybe_apply_password(changeset, %UserEntity{hashed_password: nil}), do: changeset

  defp maybe_apply_password(changeset, %UserEntity{hashed_password: hashed}) do
    Ecto.Changeset.put_change(changeset, :hashed_password, hashed)
  end

  defp maybe_apply_password_update(changeset, _schema, %UserEntity{hashed_password: nil}) do
    changeset
  end

  defp maybe_apply_password_update(changeset, schema, %UserEntity{hashed_password: hashed}) do
    # Only update if password changed
    if schema.hashed_password != hashed do
      Ecto.Changeset.put_change(changeset, :hashed_password, hashed)
    else
      changeset
    end
  end

  defp maybe_apply_confirmed_at(changeset, %UserEntity{confirmed_at: nil}), do: changeset

  defp maybe_apply_confirmed_at(changeset, %UserEntity{confirmed_at: confirmed_at}) do
    Ecto.Changeset.put_change(changeset, :confirmed_at, confirmed_at)
  end

  defp apply_filter(query, _field, nil), do: query

  defp apply_filter(query, :role, role) when is_atom(role) do
    role_string = Atom.to_string(role)
    from u in query, where: u.role == ^role_string
  end

  defp apply_filter(query, field, value) do
    from u in query, where: field(u, ^field) == ^value
  end

  defp apply_confirmed_filter(query, nil), do: query

  defp apply_confirmed_filter(query, true) do
    from u in query, where: not is_nil(u.confirmed_at)
  end

  defp apply_confirmed_filter(query, false) do
    from u in query, where: is_nil(u.confirmed_at)
  end

  defp apply_search_filter(query, nil), do: query

  defp apply_search_filter(query, search) when search != "" do
    search_term = "%#{search}%"
    from u in query, where: ilike(u.email, ^search_term)
  end

  defp apply_search_filter(query, _), do: query

  defp parse_role(role) when is_binary(role) do
    case role do
      "owner" -> :owner
      "admin" -> :admin
      "member" -> :member
      _ -> :member
    end
  end

  defp parse_role(role) when is_atom(role), do: role
  defp parse_role(_), do: :member
end
