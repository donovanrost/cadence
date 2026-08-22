defmodule Cadence.Application.Contacts.ContactOperations do
  @moduledoc """
  Write operations for planned contacts.
  """

  alias Cadence.Application.Missions.MissionOperations
  alias Cadence.Contacts.Contact
  alias Cadence.Repo

  @type organization_id :: String.t()
  @type mission_id :: String.t()

  @spec create(organization_id(), mission_id(), map()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def create(organization_id, mission_id, attrs) do
    attrs =
      attrs
      |> Map.put(:organization_id, organization_id)
      |> Map.put(:mission_id, mission_id)

    %Contact{}
    |> Contact.changeset(attrs)
    |> Repo.insert()
    |> maybe_bump_config_generation(mission_id)
  end

  @spec update(Contact.t(), map()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def update(%Contact{} = contact, attrs) do
    contact
    |> Contact.changeset(attrs)
    |> Repo.update()
    |> maybe_bump_config_generation(contact.mission_id)
  end

  @spec delete(Contact.t()) :: {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Contact{} = contact) do
    contact
    |> Repo.delete()
    |> maybe_bump_config_generation(contact.mission_id)
  end

  defp maybe_bump_config_generation({:ok, _record} = result, mission_id) do
    _ = MissionOperations.bump_config_generation!(mission_id)
    result
  end

  defp maybe_bump_config_generation(result, _mission_id), do: result
end
