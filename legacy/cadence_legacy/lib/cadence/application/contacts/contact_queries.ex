defmodule Cadence.Application.Contacts.ContactQueries do
  @moduledoc """
  Read operations for planned contacts.
  """

  import Ecto.Query

  alias Cadence.Contacts.Contact
  alias Cadence.Repo

  @type organization_id :: String.t()
  @type mission_id :: String.t()

  @spec list(organization_id(), keyword()) :: [Contact.t()]
  def list(organization_id, opts \\ []) do
    mission_id = Keyword.get(opts, :mission_id)
    state = Keyword.get(opts, :state)

    Contact
    |> where([c], c.organization_id == ^organization_id)
    |> maybe_filter(:mission_id, mission_id)
    |> maybe_filter(:state, state)
    |> order_by([c], asc: c.start_time)
    |> Repo.all()
  end

  @spec list_planned_for_mission(mission_id()) :: [Contact.t()]
  def list_planned_for_mission(mission_id) do
    Contact
    |> where([c], c.mission_id == ^mission_id and c.state == :planned)
    |> order_by([c], asc: c.start_time)
    |> Repo.all()
  end

  @spec find(String.t(), organization_id()) :: {:ok, Contact.t()} | {:error, :not_found}
  def find(id, organization_id) do
    Contact
    |> where([c], c.id == ^id and c.organization_id == ^organization_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      contact -> {:ok, contact}
    end
  end

  @spec find_for_mission(String.t(), organization_id(), mission_id()) ::
          {:ok, Contact.t()} | {:error, :not_found}
  def find_for_mission(id, organization_id, mission_id) do
    Contact
    |> where(
      [
        c
      ],
      c.id == ^id and c.organization_id == ^organization_id and c.mission_id == ^mission_id
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      contact -> {:ok, contact}
    end
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, field, value), do: where(query, [c], field(c, ^field) == ^value)
end
