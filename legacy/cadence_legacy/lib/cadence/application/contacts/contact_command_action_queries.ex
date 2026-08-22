defmodule Cadence.Application.Contacts.ContactCommandActionQueries do
  @moduledoc """
  Read operations for contact command actions.
  """

  import Ecto.Query

  alias Cadence.Contacts.ContactCommandAction
  alias Cadence.Repo

  @type organization_id :: String.t()
  @type mission_id :: String.t()

  @spec list(organization_id(), keyword()) :: [ContactCommandAction.t()]
  def list(organization_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    contact_id = Keyword.get(opts, :contact_id)
    state = Keyword.get(opts, :state)

    ContactCommandAction
    |> where([a], a.organization_id == ^organization_id)
    |> maybe_filter(:mission_id, mission_id)
    |> maybe_filter(:contact_id, contact_id)
    |> maybe_filter(:state, state)
    |> order_by([a], asc: a.order, asc: a.inserted_at, asc: a.id)
    |> Repo.all()
  end

  @spec list_planned_for_mission(mission_id()) :: [ContactCommandAction.t()]
  def list_planned_for_mission(mission_id) do
    ContactCommandAction
    |> where([a], a.mission_id == ^mission_id and a.state == :planned)
    |> order_by([a], asc: a.order, asc: a.inserted_at, asc: a.id)
    |> Repo.all()
  end

  @spec find_for_mission(String.t(), organization_id(), mission_id()) ::
          {:ok, ContactCommandAction.t()} | {:error, :not_found}
  def find_for_mission(id, organization_id, mission_id) do
    ContactCommandAction
    |> where(
      [a],
      a.id == ^id and a.organization_id == ^organization_id and a.mission_id == ^mission_id
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      action -> {:ok, action}
    end
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, field, value), do: where(query, [a], field(a, ^field) == ^value)
end
