defmodule Cadence.Contacts.ScheduledContact do
  @moduledoc """
  Mission-scoped planned operational contact definition.
  """

  alias Cadence.Contacts.{KnownAtom, Path}
  alias Cadence.Ids

  @type lifecycle_state :: :scheduled | :realized | :completed | :expired | :canceled

  @type t :: %__MODULE__{
          scheduled_contact_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          source_endpoint_refs: [binary()],
          path_template_ids: [binary()],
          path_template_refs: [map()],
          paths: [Path.t()],
          starts_at: DateTime.t(),
          ends_at: DateTime.t() | nil,
          provider_contact_ref: binary() | nil,
          lifecycle_state: lifecycle_state(),
          realized_contact_id: binary() | nil,
          metadata: map()
        }

  defstruct [
    :scheduled_contact_id,
    :organization_id,
    :mission_id,
    :starts_at,
    :ends_at,
    :provider_contact_ref,
    :realized_contact_id,
    source_endpoint_refs: [],
    path_template_ids: [],
    path_template_refs: [],
    paths: [],
    lifecycle_state: :scheduled,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      scheduled_contact_id:
        Map.get(
          attrs,
          :scheduled_contact_id,
          Map.get(attrs, "scheduled_contact_id", Ids.new("scheduled_contact"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      source_endpoint_refs:
        Map.get(attrs, :source_endpoint_refs, Map.get(attrs, "source_endpoint_refs", [])),
      path_template_ids:
        Map.get(attrs, :path_template_ids, Map.get(attrs, "path_template_ids", [])),
      path_template_refs:
        attrs
        |> Map.get(:path_template_refs, Map.get(attrs, "path_template_refs", []))
        |> Enum.map(&normalize_path_template_ref/1),
      paths:
        attrs
        |> Map.get(:paths, Map.get(attrs, "paths", []))
        |> Enum.map(&build_path/1),
      starts_at: Map.fetch!(attrs, :starts_at),
      ends_at: Map.get(attrs, :ends_at, Map.get(attrs, "ends_at")),
      provider_contact_ref:
        Map.get(attrs, :provider_contact_ref, Map.get(attrs, "provider_contact_ref")),
      lifecycle_state:
        Map.get(attrs, :lifecycle_state, Map.get(attrs, "lifecycle_state", :scheduled))
        |> normalize_lifecycle_state(),
      realized_contact_id:
        Map.get(attrs, :realized_contact_id, Map.get(attrs, "realized_contact_id")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp build_path(%Path{} = path), do: path
  defp build_path(attrs) when is_map(attrs), do: Path.new(attrs)

  defp normalize_lifecycle_state(lifecycle_state),
    do: KnownAtom.scheduled_contact_lifecycle_state!(lifecycle_state)

  defp normalize_path_template_ref(%{} = ref) do
    %{
      "path_template_id" => Map.get(ref, "path_template_id") || Map.get(ref, :path_template_id),
      "version" => Map.get(ref, "version") || Map.get(ref, :version) || 1
    }
  end
end
