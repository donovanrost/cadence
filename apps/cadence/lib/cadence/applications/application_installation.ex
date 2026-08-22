defmodule Cadence.Applications.ApplicationInstallation do
  @moduledoc "Durable, version-pinned installation of one application at one host scope."

  alias Cadence.Applications.ConfigurationReference
  alias Cadence.Ids

  @type lifecycle_state :: :installed | :disabled | :uninstalled
  @type scope_kind :: :mission | :spacecraft

  @type t :: %__MODULE__{
          application_installation_id: binary(),
          organization_id: binary(),
          mission_id: binary(),
          scope_kind: scope_kind(),
          scope_id: binary(),
          application_key: binary(),
          application_version: pos_integer(),
          configuration_ref: ConfigurationReference.t() | nil,
          lifecycle_state: lifecycle_state(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          metadata: map()
        }

  @enforce_keys [
    :application_installation_id,
    :organization_id,
    :mission_id,
    :scope_kind,
    :scope_id,
    :application_key,
    :application_version,
    :lifecycle_state
  ]

  defstruct [
    :application_installation_id,
    :organization_id,
    :mission_id,
    :scope_kind,
    :scope_id,
    :application_key,
    :application_version,
    :configuration_ref,
    :lifecycle_state,
    :inserted_at,
    :updated_at,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      application_installation_id:
        Map.get(
          attrs,
          :application_installation_id,
          Map.get(attrs, "application_installation_id", Ids.new("application_installation"))
        ),
      organization_id: fetch_attr!(attrs, :organization_id),
      mission_id: fetch_attr!(attrs, :mission_id),
      scope_kind: attrs |> fetch_attr!(:scope_kind) |> normalize_scope_kind(),
      scope_id: fetch_attr!(attrs, :scope_id),
      application_key: fetch_attr!(attrs, :application_key),
      application_version: fetch_attr!(attrs, :application_version),
      configuration_ref:
        attrs
        |> Map.get(:configuration_ref, Map.get(attrs, "configuration_ref"))
        |> normalize_configuration_ref(),
      lifecycle_state:
        attrs
        |> Map.get(:lifecycle_state, Map.get(attrs, "lifecycle_state", :installed))
        |> normalize_lifecycle_state(),
      inserted_at: Map.get(attrs, :inserted_at, Map.get(attrs, "inserted_at")),
      updated_at: Map.get(attrs, :updated_at, Map.get(attrs, "updated_at")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp normalize_configuration_ref(nil), do: nil
  defp normalize_configuration_ref(%ConfigurationReference{} = ref), do: ref

  defp normalize_configuration_ref(attrs) when is_map(attrs),
    do: ConfigurationReference.new(attrs)

  defp normalize_scope_kind(:spacecraft), do: :spacecraft
  defp normalize_scope_kind("spacecraft"), do: :spacecraft
  defp normalize_scope_kind(:mission), do: :mission
  defp normalize_scope_kind("mission"), do: :mission

  defp normalize_lifecycle_state(:installed), do: :installed
  defp normalize_lifecycle_state("installed"), do: :installed
  defp normalize_lifecycle_state(:disabled), do: :disabled
  defp normalize_lifecycle_state("disabled"), do: :disabled
  defp normalize_lifecycle_state(:uninstalled), do: :uninstalled
  defp normalize_lifecycle_state("uninstalled"), do: :uninstalled

  defp fetch_attr!(attrs, key) do
    Map.get(attrs, key) || Map.fetch!(attrs, Atom.to_string(key))
  end
end
