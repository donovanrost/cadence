defmodule Cadence.Catalog.Actor do
  @moduledoc """
  Who brought a catalog in: the document stored as an artifact's `uploaded_by`, an import run's
  `requested_by`, and a database's or revision's `created_by` (lead 11-14/11-17; imports used to
  store `%{}`).

  - A person: `{"actor_kind" => "user", "user_id", "name"}`, where `name` is the display name or
    nil. It never carries the email (#471, ca-security's P1 on #462); documents written before
    #471 may, and reads never use it.
  - A service identity: `{"actor_kind" => "service", "service_identity_id", "name"}`.
  - Cadence itself (a seed or a task): `{"actor_kind" => "system", "system_id", "name",
    "run_by"}`. `system_id` is a stable ref (e.g. the seed's id), `name` says what ran (never a
    person), and `run_by` is the user id of the person who ran it (#513, MM-2). A system actor
    without `run_by` is refused (`recorded/1`), so no import has nobody accountable for it, and the
    runner counts as an importer for the model gate's separation (`ModelImporters`).

  New documents never carry a bare `"id"`: the model approval gate's importer read
  (`Catalog.model_importers/3`) takes `"user_id"` (or, on old catalog revision rows, a legacy
  `"id"`), so only a person counts as an importer. Reads name the actor by who they are now
  (`Reads.Catalog.Requesters`, #146/#366), never by the stored `"name"` or `"email"`; the
  operational event by `user_id` or `service_identity_id`.
  """

  alias Cadence.Auth.Scope

  @type t :: %{required(binary()) => binary() | nil}

  @spec from_scope(Scope.t()) :: {:ok, t()} | {:error, :catalog_import_actor_required}
  def from_scope(%Scope{actor_kind: :user, user: %{user_id: id} = user}) when is_binary(id),
    do:
      recorded_as(%{
        "actor_kind" => "user",
        "user_id" => id,
        "name" => present(Map.get(user, :display_name))
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

  @doc """
  Cadence itself as the actor: `system_id` a stable ref, `name` what ran (never a person), and
  `run_by` the user id of the person who ran it (#513): they count as an importer, so they can't
  approve what this imports under 'independent'.
  """
  @spec system(binary(), binary(), binary()) :: t()
  def system(system_id, name, run_by)
      when is_binary(system_id) and system_id != "" and is_binary(name) and name != "" and
             is_binary(run_by) and run_by != "",
      do: %{
        "actor_kind" => "system",
        "system_id" => system_id,
        "name" => name,
        "run_by" => run_by
      }

  @doc """
  `:ok` when `actor` names who ran an import: a person's `user_id`, a service identity's
  `service_identity_id`, or a system actor's `system_id` with the person who ran it (`run_by`,
  #513). Also the REST API's document (`ControlPlaneAccess.actor_document/1`), which carries the
  same two ids.
  """
  @spec recorded(term()) :: :ok | {:error, :catalog_import_actor_required}
  def recorded(%{"user_id" => id}) when is_binary(id) and id != "", do: :ok
  def recorded(%{"service_identity_id" => id}) when is_binary(id) and id != "", do: :ok

  def recorded(%{"actor_kind" => "system", "system_id" => id, "run_by" => by})
      when is_binary(id) and id != "" and is_binary(by) and by != "",
      do: :ok

  def recorded(_actor), do: {:error, :catalog_import_actor_required}

  defp present(name) when is_binary(name) and name != "", do: name
  defp present(_none), do: nil

  defp recorded_as(actor) do
    with :ok <- recorded(actor), do: {:ok, actor}
  end
end
