defmodule Cadence.Transports do
  @moduledoc """
  Context for managing transport interfaces with mission/org scoping.
  """

  import Ecto.Query

  alias Cadence.Repo
  alias Cadence.Transports.Interface

  @type organization_id :: Ecto.UUID.t()
  @type mission_id :: Ecto.UUID.t()

  @spec create_interface(organization_id(), mission_id(), map()) ::
          {:ok, Interface.t()} | {:error, Ecto.Changeset.t()}
  def create_interface(organization_id, mission_id, attrs) do
    %Interface{}
    |> Interface.changeset(attrs, organization_id, mission_id)
    |> Repo.insert()
  end

  @spec update_interface(organization_id(), mission_id(), Interface.t(), map()) ::
          {:ok, Interface.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def update_interface(organization_id, mission_id, %Interface{} = interface, attrs) do
    if interface.organization_id == organization_id and interface.mission_id == mission_id do
      interface
      |> Interface.update_changeset(attrs)
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  @spec get_interface(organization_id(), mission_id(), Ecto.UUID.t()) ::
          {:ok, Interface.t()} | {:error, :not_found}
  def get_interface(organization_id, mission_id, interface_id) do
    interface =
      Interface
      |> where([i], i.organization_id == ^organization_id and i.mission_id == ^mission_id)
      |> Repo.get(interface_id)

    if interface, do: {:ok, interface}, else: {:error, :not_found}
  end

  @spec list_interfaces(organization_id(), mission_id()) :: [Interface.t()]
  def list_interfaces(organization_id, mission_id) do
    Interface
    |> where([i], i.organization_id == ^organization_id and i.mission_id == ^mission_id)
    |> order_by([i], asc: i.name)
    |> Repo.all()
  end

  @spec get_interface!(organization_id(), mission_id(), Ecto.UUID.t()) :: Interface.t()
  def get_interface!(organization_id, mission_id, interface_id) do
    Interface
    |> where([i], i.organization_id == ^organization_id and i.mission_id == ^mission_id)
    |> Repo.get!(interface_id)
  end

  @spec delete_interface(organization_id(), mission_id(), Interface.t()) ::
          {:ok, Interface.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def delete_interface(organization_id, mission_id, %Interface{} = interface) do
    if interface.organization_id == organization_id and interface.mission_id == mission_id do
      Repo.delete(interface)
    else
      {:error, :unauthorized}
    end
  end

  @spec change_interface(Interface.t()) :: Ecto.Changeset.t()
  def change_interface(%Interface{} = interface) do
    Interface.update_changeset(interface, %{})
  end

  @spec change_interface(Interface.t(), map()) :: Ecto.Changeset.t()
  def change_interface(%Interface{} = interface, attrs) do
    Interface.update_changeset(interface, attrs)
  end
end
