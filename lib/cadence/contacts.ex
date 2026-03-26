defmodule Cadence.Contacts do
  @moduledoc """
  Context facade for planned contacts.

  Delegates:
  - `Cadence.Application.Contacts.ContactQueries` for read operations
  - `Cadence.Application.Contacts.ContactOperations` for write operations
  """

  alias Cadence.Application.Contacts.{
    ContactCommandActionOperations,
    ContactCommandActionQueries,
    ContactOperations,
    ContactQueries
  }

  alias Cadence.Contacts.{Contact, ContactCommandAction}

  @type organization_id :: String.t()
  @type mission_id :: String.t()

  @spec list_contacts(organization_id(), keyword()) :: [Contact.t()]
  def list_contacts(organization_id, opts \\ []) do
    ContactQueries.list(organization_id, opts)
  end

  @spec list_planned_contacts(mission_id()) :: [Contact.t()]
  def list_planned_contacts(mission_id) do
    ContactQueries.list_planned_for_mission(mission_id)
  end

  @spec get_contact(String.t(), organization_id(), mission_id()) ::
          {:ok, Contact.t()} | {:error, :not_found}
  def get_contact(id, organization_id, mission_id) do
    ContactQueries.find_for_mission(id, organization_id, mission_id)
  end

  @spec create_contact(organization_id(), mission_id(), map()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()}
  def create_contact(organization_id, mission_id, attrs) do
    ContactOperations.create(organization_id, mission_id, attrs)
  end

  @spec list_contact_command_actions(organization_id(), keyword()) :: [ContactCommandAction.t()]
  def list_contact_command_actions(organization_id, opts \\ []) do
    ContactCommandActionQueries.list(organization_id, opts)
  end

  @spec get_contact_command_action(String.t(), organization_id(), mission_id()) ::
          {:ok, ContactCommandAction.t()} | {:error, :not_found}
  def get_contact_command_action(id, organization_id, mission_id) do
    ContactCommandActionQueries.find_for_mission(id, organization_id, mission_id)
  end

  @spec create_contact_command_action(organization_id(), mission_id(), map()) ::
          {:ok, ContactCommandAction.t()} | {:error, Ecto.Changeset.t()}
  def create_contact_command_action(organization_id, mission_id, attrs) do
    ContactCommandActionOperations.create(organization_id, mission_id, attrs)
  end

  @spec update_contact_command_action(
          organization_id(),
          mission_id(),
          ContactCommandAction.t(),
          map()
        ) ::
          {:ok, ContactCommandAction.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :unauthorized}
  def update_contact_command_action(
        organization_id,
        mission_id,
        %ContactCommandAction{} = action,
        attrs
      ) do
    if action.organization_id == organization_id and action.mission_id == mission_id do
      ContactCommandActionOperations.update(action, attrs)
    else
      {:error, :unauthorized}
    end
  end

  @spec delete_contact_command_action(organization_id(), mission_id(), ContactCommandAction.t()) ::
          {:ok, ContactCommandAction.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def delete_contact_command_action(organization_id, mission_id, %ContactCommandAction{} = action) do
    if action.organization_id == organization_id and action.mission_id == mission_id do
      ContactCommandActionOperations.delete(action)
    else
      {:error, :unauthorized}
    end
  end

  @spec update_contact(organization_id(), mission_id(), Contact.t(), map()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def update_contact(organization_id, mission_id, %Contact{} = contact, attrs) do
    if contact.organization_id == organization_id and contact.mission_id == mission_id do
      ContactOperations.update(contact, attrs)
    else
      {:error, :unauthorized}
    end
  end

  @spec delete_contact(organization_id(), mission_id(), Contact.t()) ::
          {:ok, Contact.t()} | {:error, Ecto.Changeset.t()} | {:error, :unauthorized}
  def delete_contact(organization_id, mission_id, %Contact{} = contact) do
    if contact.organization_id == organization_id and contact.mission_id == mission_id do
      ContactOperations.delete(contact)
    else
      {:error, :unauthorized}
    end
  end
end
