defmodule CadenceWeb.Schemas.TargetForm do
  @moduledoc """
  Embedded schema for target forms in LiveView.

  This schema provides form validation without database persistence.
  It's used for creating and editing targets through the web interface.

  ## Target Types

  - `spacecraft` - An orbiting or in-flight vehicle
  - `ground_station` - A ground-based communication facility
  - `simulator` - A software simulator for testing
  - `relay` - A relay satellite or communication node

  ## Usage

      # In LiveView
      def mount(_params, _session, socket) do
        form = TargetForm.changeset() |> to_form()
        {:ok, assign(socket, form: form)}
      end

      def handle_event("validate", %{"target_form" => params}, socket) do
        form =
          TargetForm.changeset(params)
          |> Map.put(:action, :validate)
          |> to_form()

        {:noreply, assign(socket, form: form)}
      end

      def handle_event("save", %{"target_form" => params}, socket) do
        case TargetForm.changeset(params) |> Ecto.Changeset.apply_action(:insert) do
          {:ok, form} ->
            attrs = TargetForm.to_domain_attrs(form)
            TargetOperations.create(mission_id, attrs)
          {:error, changeset} ->
            {:noreply, assign(socket, form: to_form(changeset))}
        end
      end
  """

  use Ecto.Schema
  import Ecto.Changeset

  @target_types [:spacecraft, :ground_station, :simulator, :relay]
  @target_statuses [:offline, :online, :standby, :fault]

  @primary_key false
  embedded_schema do
    field :name, :string
    field :identifier, :string
    field :type, Ecto.Enum, values: @target_types, default: :spacecraft
    field :definition_set_id, :binary_id
    field :active_limit_set, :string, default: "NOMINAL"
    field :config, :map, default: %{}
    field :metadata, :map, default: %{}
    # UI-only fields
    field :status, Ecto.Enum, values: @target_statuses, default: :offline
  end

  @doc """
  Creates a changeset for the target form.

  ## Examples

      TargetForm.changeset(%{name: "ISS", identifier: "ISS_001", type: :spacecraft})
  """
  def changeset(form \\ %__MODULE__{}, attrs \\ %{}) do
    form
    |> cast(attrs, [
      :name,
      :identifier,
      :type,
      :definition_set_id,
      :active_limit_set,
      :config,
      :metadata,
      :status
    ])
    |> validate_required([:name, :identifier, :type, :definition_set_id])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:identifier, min: 1, max: 50)
    |> validate_identifier_format()
    |> validate_length(:active_limit_set, max: 100)
  end

  @doc """
  Converts a form struct to domain attributes for creating/updating a target.
  """
  def to_domain_attrs(%__MODULE__{} = form) do
    %{
      name: form.name,
      identifier: form.identifier,
      type: form.type,
      definition_set_id: form.definition_set_id,
      active_limit_set: form.active_limit_set,
      config: form.config || %{},
      metadata: form.metadata || %{}
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Creates a form struct from a domain entity for editing.
  """
  def from_entity(%Cadence.Domain.Targeting.Entities.Target{} = entity) do
    %__MODULE__{
      name: entity.name,
      identifier: entity.identifier,
      type: entity.type,
      definition_set_id: entity.definition_set_id,
      active_limit_set: entity.active_limit_set,
      config: entity.config || %{},
      metadata: entity.metadata || %{},
      status: entity.status
    }
  end

  @doc """
  Returns the list of available target types.
  """
  def target_types, do: @target_types

  @doc """
  Returns the list of available target statuses.
  """
  def target_statuses, do: @target_statuses

  @doc """
  Returns a human-readable label for a target type.
  """
  def type_label(:spacecraft), do: "Spacecraft"
  def type_label(:ground_station), do: "Ground Station"
  def type_label(:simulator), do: "Simulator"
  def type_label(:relay), do: "Relay"
  def type_label(_), do: "Unknown"

  # Private helpers

  defp validate_identifier_format(changeset) do
    validate_format(changeset, :identifier, ~r/^[A-Z0-9_-]+$/,
      message: "must be uppercase alphanumeric with underscores or hyphens"
    )
  end
end
