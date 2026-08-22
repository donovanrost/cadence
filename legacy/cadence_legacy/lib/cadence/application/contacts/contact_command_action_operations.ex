defmodule Cadence.Application.Contacts.ContactCommandActionOperations do
  @moduledoc """
  Write operations for contact command actions.
  """

  alias Cadence.Application.Missions.MissionOperations
  alias Cadence.Contacts.ContactCommandAction
  alias Cadence.Repo

  @type organization_id :: String.t()
  @type mission_id :: String.t()

  @spec create(organization_id(), mission_id(), map()) ::
          {:ok, ContactCommandAction.t()} | {:error, Ecto.Changeset.t()}
  def create(organization_id, mission_id, attrs) do
    attrs =
      attrs
      |> Map.put(:organization_id, organization_id)
      |> Map.put(:mission_id, mission_id)

    %ContactCommandAction{}
    |> ContactCommandAction.changeset(attrs)
    |> Repo.insert()
    |> maybe_bump_config_generation(mission_id)
  end

  @spec update(ContactCommandAction.t(), map()) ::
          {:ok, ContactCommandAction.t()} | {:error, Ecto.Changeset.t()}
  def update(%ContactCommandAction{} = action, attrs) do
    action
    |> ContactCommandAction.changeset(attrs)
    |> Repo.update()
    |> maybe_bump_config_generation(action.mission_id)
  end

  @spec delete(ContactCommandAction.t()) ::
          {:ok, ContactCommandAction.t()} | {:error, Ecto.Changeset.t()}
  def delete(%ContactCommandAction{} = action) do
    action
    |> Repo.delete()
    |> maybe_bump_config_generation(action.mission_id)
  end

  defp maybe_bump_config_generation({:ok, _record} = result, mission_id) do
    _ = MissionOperations.bump_config_generation!(mission_id)
    result
  end

  defp maybe_bump_config_generation(result, _mission_id), do: result
end
