defmodule CadenceWeb.Schemas.MissionForm do
  @moduledoc """
  Embedded schema for mission forms in LiveView.

  This schema provides form validation without database persistence.
  It's used for creating and editing missions through the web interface.

  ## Usage

      # In LiveView
      def mount(_params, _session, socket) do
        form = MissionForm.changeset() |> to_form()
        {:ok, assign(socket, form: form)}
      end

      def handle_event("validate", %{"mission_form" => params}, socket) do
        form =
          MissionForm.changeset(params)
          |> Map.put(:action, :validate)
          |> to_form()

        {:noreply, assign(socket, form: form)}
      end

      def handle_event("save", %{"mission_form" => params}, socket) do
        case MissionForm.changeset(params) |> Ecto.Changeset.apply_action(:insert) do
          {:ok, form} ->
            attrs = MissionForm.to_domain_attrs(form)
            Missions.create_mission_with_bucket(org_id, attrs)
          {:error, changeset} ->
            {:noreply, assign(socket, form: to_form(changeset))}
        end
      end
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :phase, Ecto.Enum, values: [:planning, :testing, :operational, :decommissioned]
    field :start_date, :date
    field :end_date, :date
    field :config, :map, default: %{}
    field :metadata, :map, default: %{}
  end

  @doc """
  Creates a changeset for the mission form.

  ## Examples

      MissionForm.changeset(%{name: "ISS Ops", slug: "iss-ops"})
  """
  def changeset(form \\ %__MODULE__{}, attrs \\ %{}) do
    form
    |> cast(attrs, [
      :name,
      :slug,
      :description,
      :phase,
      :start_date,
      :end_date,
      :config,
      :metadata
    ])
    |> validate_required([:name, :slug])
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must be lowercase alphanumeric with hyphens"
    )
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:slug, min: 1, max: 100)
    |> validate_date_range()
  end

  @doc """
  Converts a form struct to domain attributes for creating/updating a mission.
  """
  def to_domain_attrs(%__MODULE__{} = form) do
    %{
      name: form.name,
      slug: form.slug,
      description: form.description,
      phase: form.phase,
      start_date: form.start_date,
      end_date: form.end_date,
      config: form.config || %{},
      metadata: form.metadata || %{}
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Creates a form struct from a domain entity for editing.
  """
  def from_entity(%Cadence.Domain.Missions.Entities.Mission{} = entity) do
    %__MODULE__{
      name: entity.name,
      slug: entity.slug,
      description: entity.description,
      phase: entity.phase,
      start_date: entity.start_date && Date.from_iso8601!(Date.to_iso8601(entity.start_date)),
      end_date: entity.end_date && Date.from_iso8601!(Date.to_iso8601(entity.end_date)),
      config: entity.config || %{},
      metadata: entity.metadata || %{}
    }
  end

  defp validate_date_range(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)

    if start_date && end_date && Date.compare(start_date, end_date) == :gt do
      add_error(changeset, :end_date, "must be after start date")
    else
      changeset
    end
  end
end
