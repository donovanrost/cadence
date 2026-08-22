defmodule Cadence.Contacts.RealizedContact do
  @moduledoc """
  Mission-scoped realized operational contact definition.
  """

  alias Cadence.Contacts.{KnownAtom, Path}
  alias Cadence.Ids

  @type clock_mode :: :live | :replay
  @type lifecycle_state :: :defined | :active | :stopped | :completed

  @type t :: %__MODULE__{
          realized_contact_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          scheduled_contact_id: binary() | nil,
          source_endpoint_refs: [binary()],
          contact_intents: [atom()],
          paths: [Path.t()],
          clock_mode: clock_mode(),
          initial_time: DateTime.t() | nil,
          lifecycle_state: lifecycle_state(),
          realized_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :realized_contact_id,
    :organization_id,
    :mission_id,
    :scheduled_contact_id,
    :initial_time,
    :realized_at,
    source_endpoint_refs: [],
    contact_intents: [],
    paths: [],
    clock_mode: :live,
    lifecycle_state: :defined,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      realized_contact_id:
        Map.get(
          attrs,
          :realized_contact_id,
          Map.get(attrs, "realized_contact_id", Ids.new("realized_contact"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      scheduled_contact_id:
        Map.get(attrs, :scheduled_contact_id, Map.get(attrs, "scheduled_contact_id")),
      source_endpoint_refs:
        Map.get(attrs, :source_endpoint_refs, Map.get(attrs, "source_endpoint_refs", [])),
      contact_intents:
        attrs
        |> Map.get(:contact_intents, Map.get(attrs, "contact_intents", []))
        |> Enum.map(&KnownAtom.contact_intent!/1),
      paths:
        attrs
        |> Map.get(:paths, Map.get(attrs, "paths", []))
        |> Enum.map(&build_path/1),
      clock_mode:
        Map.get(attrs, :clock_mode, Map.get(attrs, "clock_mode", :live))
        |> normalize_clock_mode(),
      initial_time: Map.get(attrs, :initial_time, Map.get(attrs, "initial_time")),
      lifecycle_state:
        Map.get(attrs, :lifecycle_state, Map.get(attrs, "lifecycle_state", :defined))
        |> normalize_lifecycle_state(),
      realized_at: Map.get(attrs, :realized_at, Map.get(attrs, "realized_at")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp build_path(%Path{} = path), do: path
  defp build_path(attrs) when is_map(attrs), do: Path.new(attrs)

  defp normalize_clock_mode(clock_mode), do: KnownAtom.clock_mode!(clock_mode)

  defp normalize_lifecycle_state(lifecycle_state),
    do: KnownAtom.realized_contact_lifecycle_state!(lifecycle_state)
end
