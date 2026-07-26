defmodule Cadence.Applications.ApplicationInstallations.InstallationRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Applications.{ApplicationInstallation, ConfigurationReference}
  alias Cadence.Persistence.JsonDocument

  @primary_key {:application_installation_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "application_installations" do
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:scope_kind, :string)
    field(:scope_id, :string)
    field(:spacecraft_id, :string)
    field(:application_key, :string)
    field(:application_version, :integer)
    field(:configuration_kind, :string)
    field(:configuration_id, :string)
    field(:configuration_version, :integer)
    field(:lifecycle_state, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @fields [
    :application_installation_id,
    :organization_id,
    :mission_id,
    :scope_kind,
    :scope_id,
    :spacecraft_id,
    :application_key,
    :application_version,
    :configuration_kind,
    :configuration_id,
    :configuration_version,
    :lifecycle_state,
    :metadata
  ]

  @required_fields [
    :application_installation_id,
    :organization_id,
    :mission_id,
    :scope_kind,
    :scope_id,
    :application_key,
    :application_version,
    :lifecycle_state,
    :metadata
  ]

  @spec changeset(struct(), ApplicationInstallation.t()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = row, %ApplicationInstallation{} = installation) do
    row
    |> cast(domain_attrs(installation), @fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:scope_kind, ["mission", "spacecraft"])
    |> validate_scope_reference()
    |> validate_inclusion(:lifecycle_state, ["installed", "disabled", "uninstalled"])
    |> validate_number(:application_version, greater_than: 0)
    |> validate_configuration_reference()
    |> unique_constraint(
      [:organization_id, :mission_id, :scope_kind, :scope_id, :application_key],
      name: :application_installations_scope_idx
    )
  end

  @spec to_domain(struct()) :: ApplicationInstallation.t()
  def to_domain(%__MODULE__{} = row) do
    ApplicationInstallation.new(%{
      application_installation_id: row.application_installation_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      scope_kind: row.scope_kind,
      scope_id: row.scope_id,
      application_key: row.application_key,
      application_version: row.application_version,
      configuration_ref: configuration_ref(row),
      lifecycle_state: row.lifecycle_state,
      inserted_at: row.inserted_at,
      updated_at: row.updated_at,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%ApplicationInstallation{} = installation) do
    ref = installation.configuration_ref

    %{
      application_installation_id: installation.application_installation_id,
      organization_id: installation.organization_id,
      mission_id: installation.mission_id,
      scope_kind: Atom.to_string(installation.scope_kind),
      scope_id: installation.scope_id,
      spacecraft_id:
        if(installation.scope_kind == :spacecraft, do: installation.scope_id, else: nil),
      application_key: installation.application_key,
      application_version: installation.application_version,
      configuration_kind: ref && ref.kind,
      configuration_id: ref && ref.id,
      configuration_version: ref && ref.version,
      lifecycle_state: Atom.to_string(installation.lifecycle_state),
      metadata: JsonDocument.wrap_value(installation.metadata)
    }
  end

  defp configuration_ref(%__MODULE__{
         configuration_kind: kind,
         configuration_id: id,
         configuration_version: version
       })
       when is_binary(kind) and is_binary(id) and is_integer(version) do
    %ConfigurationReference{kind: kind, id: id, version: version}
  end

  defp configuration_ref(%__MODULE__{}), do: nil

  defp validate_configuration_reference(changeset) do
    values =
      Enum.map(
        [:configuration_kind, :configuration_id, :configuration_version],
        &get_field(changeset, &1)
      )

    cond do
      Enum.all?(values, &is_nil/1) ->
        changeset

      Enum.all?(values, &(not is_nil(&1))) ->
        validate_number(changeset, :configuration_version, greater_than: 0)

      true ->
        add_error(
          changeset,
          :configuration_version,
          "must identify a complete configuration reference"
        )
    end
  end

  defp validate_scope_reference(changeset) do
    case {
      get_field(changeset, :scope_kind),
      get_field(changeset, :scope_id),
      get_field(changeset, :mission_id),
      get_field(changeset, :spacecraft_id)
    } do
      {"mission", scope_id, scope_id, nil} ->
        changeset

      {"spacecraft", scope_id, _mission_id, scope_id} when is_binary(scope_id) ->
        changeset

      _other ->
        add_error(changeset, :scope_id, "must match the typed host scope")
    end
  end
end
