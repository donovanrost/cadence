defmodule Cadence.Adapters.Persistence.Ecto.Settings.EctoSettingsRepository do
  @moduledoc """
  Ecto-based implementation of the SettingsRepository port.

  This adapter provides persistence for settings using PostgreSQL via Ecto.

  ## Usage

  This module is typically injected via configuration:

      config :cadence, :settings_repository, Cadence.Adapters.Persistence.Ecto.Settings.EctoSettingsRepository

  Then accessed via:

      repo = Cadence.Ports.Repository.Settings.SettingsRepository.impl()
      {:ok, setting} = repo.find(scope_id, scope_type, namespace, key)
  """

  @behaviour Cadence.Ports.Repository.Settings.SettingsRepository

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Settings.Setting

  # ===========================================================================
  # Setting Operations
  # ===========================================================================

  @impl true
  def find(scope_id, scope_type, namespace, key) do
    query =
      from s in Setting,
        where:
          s.scope_id == ^scope_id and
            s.scope_type == ^scope_type and
            s.namespace == ^to_string(namespace) and
            s.key == ^to_string(key)

    case Repo.one(query) do
      nil -> {:error, :not_found}
      setting -> {:ok, setting}
    end
  end

  @impl true
  def get_value(scope_id, scope_type, namespace, key) do
    query =
      from s in Setting,
        where:
          s.scope_id == ^scope_id and
            s.scope_type == ^scope_type and
            s.namespace == ^to_string(namespace) and
            s.key == ^to_string(key),
        select: s.value

    Repo.one(query)
  end

  @impl true
  def list_by_scope(scope_id, scope_type, opts \\ []) do
    namespace = Keyword.get(opts, :namespace)

    query =
      from s in Setting,
        where: s.scope_id == ^scope_id and s.scope_type == ^scope_type,
        order_by: [asc: s.namespace, asc: s.key]

    query = apply_filters(query, namespace: namespace)

    Repo.all(query)
  end

  @impl true
  def upsert(attrs) do
    scope_id = Map.get(attrs, :scope_id) || Map.get(attrs, "scope_id")
    scope_type = Map.get(attrs, :scope_type) || Map.get(attrs, "scope_type")
    namespace = Map.get(attrs, :namespace) || Map.get(attrs, "namespace")
    key = Map.get(attrs, :key) || Map.get(attrs, "key")

    # Normalize attrs to have string namespace/key
    normalized_attrs =
      attrs
      |> Map.put(:namespace, to_string(namespace))
      |> Map.put(:key, to_string(key))

    # Try to find existing setting
    query =
      from s in Setting,
        where:
          s.scope_type == ^scope_type and
            s.scope_id == ^scope_id and
            s.namespace == ^to_string(namespace) and
            s.key == ^to_string(key)

    case Repo.one(query) do
      nil ->
        %Setting{}
        |> Setting.changeset(normalized_attrs)
        |> Repo.insert()

      existing ->
        existing
        |> Setting.changeset(normalized_attrs)
        |> Repo.update()
    end
  end

  @impl true
  def delete(scope_id, scope_type, namespace, key) do
    query =
      from s in Setting,
        where:
          s.scope_id == ^scope_id and
            s.scope_type == ^scope_type and
            s.namespace == ^to_string(namespace) and
            s.key == ^to_string(key)

    case Repo.delete_all(query) do
      {count, _} -> {:ok, count}
    end
  end

  @impl true
  def delete_all_for_scope(scope_id, scope_type) do
    query =
      from s in Setting,
        where: s.scope_id == ^scope_id and s.scope_type == ^scope_type

    case Repo.delete_all(query) do
      {count, _} -> {:ok, count}
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:namespace, nil}, q -> q
      {:namespace, ns}, q -> from(s in q, where: s.namespace == ^to_string(ns))
    end)
  end
end
