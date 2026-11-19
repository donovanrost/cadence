defmodule Cadence.Catalog.Actor do
  @moduledoc """
  Who brought a catalog in: the document stored as an artifact's `uploaded_by`, an import run's
  `requested_by`, and a database's or revision's `created_by` (lead 11-14/11-17; imports used to
  store `%{}`).

  - A person: `{"actor_kind" => "user", "user_id", "name", "email"}`.
  - A service identity: `{"actor_kind" => "service", "service_identity_id", "name"}`.
  - Cadence itself (a seed or a task): `{"actor_kind" => "system", "system_id", "name"}`, where
    `system_id` is a stable ref (e.g. the seed's id) and `name` says what ran, never a person.

  New documents never carry a bare `"id"`: the model approval gate's importer read
  (`Catalog.model_importers/3`) takes `"user_id"` (or, on old catalog revision rows, a legacy
  `"id"`), so only a person counts as an importer. The catalog read names the actor
  by `"name"`, else `"email"`; the operational event by `user_id` or `service_identity_id`.
  """

  alias Cadence.Auth.Scope

  @type t :: %{required(binary()) => binary() | nil}

  @spec from_scope(Scope.t()) :: {:ok, t()} | {:error, :catalog_import_actor_required}
  def from_scope(%Scope{actor_kind: :user, user: %{user_id: id} = user}) when is_binary(id),
    do:
      recorded_as(%{
        "actor_kind" => "user",
        "user_id" => id,
        "name" => Map.get(user, :display_name),
        "email" => Map.get(user, :email)
      })

  def from_scope(%Scope{actor_kind: :service, service_identity: %{service_identity_id: id} = s})
      when is_binary(id),
      do:
        recorded_as(%{
          "actor_kind" => "service",
          "service_identity_id" => id,
          "name" => Map.get(s, :display_name)
        })

  def from_scope(_scope), do: {:error, :catalog_import_actor_required}

  @doc "Cadence itself as the actor: `system_id` a stable ref, `name` what ran (never a person)."
  @spec system(binary(), binary()) :: t()
  def system(system_id, name)
      when is_binary(system_id) and system_id != "" and is_binary(name) and name != "",
      do: %{"actor_kind" => "system", "system_id" => system_id, "name" => name}

  @doc """
  `:ok` when `actor` names who ran an import: a person's `user_id`, a service identity's
  `service_identity_id`, or a system actor's `system_id`. Also the REST API's document
  (`ControlPlaneAccess.actor_document/1`), which carries the same two ids.
  """
  @spec recorded(term()) :: :ok | {:error, :catalog_import_actor_required}
  def recorded(%{"user_id" => id}) when is_binary(id) and id != "", do: :ok
  def recorded(%{"service_identity_id" => id}) when is_binary(id) and id != "", do: :ok

  def recorded(%{"actor_kind" => "system", "system_id" => id}) when is_binary(id) and id != "",
    do: :ok

  def recorded(_actor), do: {:error, :catalog_import_actor_required}

  defp recorded_as(actor) do
    with :ok <- recorded(actor), do: {:ok, actor}
  end
end
