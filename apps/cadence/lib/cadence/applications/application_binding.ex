defmodule Cadence.Applications.ApplicationBinding do
  @moduledoc """
  Spacecraft-scoped application input binding.

  This is the setup-level claim that an application handles selected packet
  APIDs for one spacecraft and catalog revision. Application-specific modules
  can adapt this generic shape into their own public config structs.
  """

  alias Cadence.Ids

  @type t :: %__MODULE__{
          application_binding_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          spacecraft_id: binary(),
          application_key: binary(),
          configuration_version: pos_integer(),
          catalog_revision_id: binary(),
          handled_apids: [non_neg_integer()],
          source_endpoint_id: binary(),
          enabled: boolean(),
          applied_binding_set_id: binary() | nil,
          applied_binding_set_version: pos_integer() | nil,
          applied_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :application_binding_id,
    :organization_id,
    :mission_id,
    :spacecraft_id,
    :application_key,
    :configuration_version,
    :catalog_revision_id,
    :source_endpoint_id,
    :applied_binding_set_id,
    :applied_binding_set_version,
    :applied_at,
    :updated_at,
    enabled: true,
    handled_apids: [],
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    application_key =
      attrs
      |> Map.get(:application_key, Map.get(attrs, "application_key"))
      |> normalize_application_key()

    spacecraft_id = fetch_attr!(attrs, :spacecraft_id)

    %__MODULE__{
      application_binding_id:
        Map.get(
          attrs,
          :application_binding_id,
          Map.get(attrs, "application_binding_id", default_id(spacecraft_id, application_key))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: fetch_attr!(attrs, :mission_id),
      spacecraft_id: spacecraft_id,
      application_key: application_key,
      configuration_version:
        Map.get(attrs, :configuration_version, Map.get(attrs, "configuration_version", 1)),
      catalog_revision_id:
        Map.get(attrs, :catalog_revision_id, Map.get(attrs, "catalog_revision_id")),
      handled_apids: Map.get(attrs, :handled_apids, Map.get(attrs, "handled_apids", [])),
      source_endpoint_id:
        Map.get(attrs, :source_endpoint_id, Map.get(attrs, "source_endpoint_id")),
      enabled: Map.get(attrs, :enabled, Map.get(attrs, "enabled", true)),
      applied_binding_set_id:
        Map.get(attrs, :applied_binding_set_id, Map.get(attrs, "applied_binding_set_id")),
      applied_binding_set_version:
        Map.get(
          attrs,
          :applied_binding_set_version,
          Map.get(attrs, "applied_binding_set_version")
        ),
      applied_at: Map.get(attrs, :applied_at, Map.get(attrs, "applied_at")),
      updated_at: Map.get(attrs, :updated_at, Map.get(attrs, "updated_at")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp default_id(spacecraft_id, application_key)
       when is_binary(spacecraft_id) and is_binary(application_key) do
    "application_binding:#{spacecraft_id}:#{application_key}"
  end

  defp default_id(_spacecraft_id, _application_key), do: Ids.new("application_binding")

  defp normalize_application_key(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_application_key(value) when is_binary(value), do: value

  defp fetch_attr!(attrs, key) do
    Map.get(attrs, key) || Map.fetch!(attrs, Atom.to_string(key))
  end
end
