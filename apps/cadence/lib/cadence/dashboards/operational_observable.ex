defmodule Cadence.Dashboards.OperationalObservable do
  @moduledoc """
  First-party semantic registry for Cadence-produced operational observables.

  Operational observables describe runtime, comms, contact, and platform facts
  produced by Cadence itself rather than dictionary-bound spacecraft telemetry.
  The registry is intentionally semantic: it defines stable ids, value shape,
  scope expectations, and ownership before every observable has a dedicated
  storage adapter.
  """

  @type value_kind :: :metric | :state
  @type value_type :: :integer | :float | :boolean | :string | :enum
  @type scope_kind ::
          :mission
          | :spacecraft
          | :contact
          | :ground_station
          | :source_endpoint
          | :transport
          | :link

  @type t :: %__MODULE__{
          observable_id: binary(),
          name: binary(),
          description: binary(),
          owner: atom(),
          logical_source: :operational_observables,
          value_kind: value_kind(),
          value_type: value_type(),
          unit: binary() | nil,
          enum_values: [atom()],
          primary_scope: scope_kind(),
          optional_scopes: [scope_kind()],
          product: atom(),
          storage: :projection | :runtime_stream | :adapter,
          state_color_policy: atom() | nil,
          version: pos_integer()
        }

  defstruct [
    :observable_id,
    :name,
    :description,
    :owner,
    :value_kind,
    :value_type,
    :unit,
    :primary_scope,
    :product,
    :storage,
    :state_color_policy,
    logical_source: :operational_observables,
    enum_values: [],
    optional_scopes: [],
    version: 1
  ]

  @definition_attrs [
    %{
      observable_id: "comms.transport.downlink_bitrate",
      name: "Downlink bit rate",
      description: "Observed downlink throughput for a transport path.",
      owner: :comms,
      value_kind: :metric,
      value_type: :float,
      unit: "bit/s",
      primary_scope: :transport,
      optional_scopes: [:spacecraft, :contact, :ground_station, :source_endpoint, :link],
      product: :comms_transport,
      storage: :projection
    },
    %{
      observable_id: "comms.transport.uplink_bitrate",
      name: "Uplink bit rate",
      description: "Observed uplink throughput for a transport path.",
      owner: :comms,
      value_kind: :metric,
      value_type: :float,
      unit: "bit/s",
      primary_scope: :transport,
      optional_scopes: [:spacecraft, :contact, :ground_station, :source_endpoint, :link],
      product: :comms_transport,
      storage: :projection
    },
    %{
      observable_id: "comms.transport.execution_state",
      name: "Transport execution state",
      description: "Runtime execution state snapshots emitted by transport capability records.",
      owner: :comms,
      value_kind: :state,
      value_type: :enum,
      enum_values: [
        :initialized,
        :transport_event_handled,
        :control_input_handled,
        :timer_handled,
        :unknown
      ],
      primary_scope: :transport,
      optional_scopes: [:spacecraft, :contact, :source_endpoint, :ground_station, :link],
      product: :comms_transport,
      storage: :projection,
      state_color_policy: :transport_execution_state
    },
    %{
      observable_id: "comms.transport.connection_state",
      name: "Transport connection state",
      description: "Connection state for a comms transport or provider path.",
      owner: :comms,
      value_kind: :state,
      value_type: :enum,
      enum_values: [:connected, :connecting, :degraded, :disconnected, :unknown],
      primary_scope: :transport,
      optional_scopes: [:mission, :spacecraft, :contact, :ground_station, :source_endpoint, :link],
      product: :comms_transport,
      storage: :projection,
      state_color_policy: :connection_state
    },
    %{
      observable_id: "ground.station.connection_state",
      name: "Ground station connection state",
      description: "Connection state between Cadence and a ground station endpoint.",
      owner: :ground_network,
      value_kind: :state,
      value_type: :enum,
      enum_values: [:connected, :connecting, :degraded, :disconnected, :unknown],
      primary_scope: :ground_station,
      optional_scopes: [:mission, :source_endpoint, :transport, :link],
      product: :ground_station,
      storage: :projection,
      state_color_policy: :connection_state
    },
    %{
      observable_id: "ground.station.antenna_pointing_state",
      name: "Antenna pointing state",
      description: "Pointing and acquisition state for a configured ground-station antenna.",
      owner: :ground_network,
      value_kind: :state,
      value_type: :enum,
      enum_values: [:idle, :slewing, :acquiring, :tracking, :stowed, :degraded, :unknown],
      primary_scope: :ground_station,
      optional_scopes: [:mission, :contact, :source_endpoint, :transport, :link],
      product: :ground_station,
      storage: :projection,
      state_color_policy: :antenna_pointing_state
    },
    %{
      observable_id: "link.rf_lock_state",
      name: "RF lock state",
      description: "Receiver lock state for a configured RF/link path.",
      owner: :comms,
      value_kind: :state,
      value_type: :enum,
      enum_values: [:locked, :acquiring, :degraded, :unlocked, :unknown],
      primary_scope: :link,
      optional_scopes: [:spacecraft, :contact, :ground_station, :source_endpoint, :transport],
      product: :link_rf,
      storage: :adapter,
      state_color_policy: :lock_state
    },
    %{
      observable_id: "link.frame_sync_state",
      name: "Frame sync state",
      description: "Frame synchronization state for a configured RF/link path.",
      owner: :comms,
      value_kind: :state,
      value_type: :enum,
      enum_values: [:synchronized, :acquiring, :degraded, :lost, :unknown],
      primary_scope: :link,
      optional_scopes: [:spacecraft, :contact, :ground_station, :source_endpoint, :transport],
      product: :link_rf,
      storage: :adapter,
      state_color_policy: :frame_sync_state
    },
    %{
      observable_id: "link.snr_db",
      name: "RF SNR",
      description: "Observed signal-to-noise ratio for a configured RF/link path.",
      owner: :comms,
      value_kind: :metric,
      value_type: :float,
      unit: "dB",
      primary_scope: :link,
      optional_scopes: [:spacecraft, :contact, :ground_station, :source_endpoint, :transport],
      product: :link_rf,
      storage: :adapter
    },
    %{
      observable_id: "link.eb_n0_db",
      name: "RF Eb/N0",
      description:
        "Observed energy-per-bit to noise-density ratio for a configured RF/link path.",
      owner: :comms,
      value_kind: :metric,
      value_type: :float,
      unit: "dB",
      primary_scope: :link,
      optional_scopes: [:spacecraft, :contact, :ground_station, :source_endpoint, :transport],
      product: :link_rf,
      storage: :adapter
    },
    %{
      observable_id: "link.symbol_rate_sps",
      name: "RF symbol rate",
      description: "Observed symbol rate for a configured RF/link path.",
      owner: :comms,
      value_kind: :metric,
      value_type: :float,
      unit: "sym/s",
      primary_scope: :link,
      optional_scopes: [:spacecraft, :contact, :ground_station, :source_endpoint, :transport],
      product: :link_rf,
      storage: :adapter
    },
    %{
      observable_id: "link.doppler_hz",
      name: "RF Doppler",
      description: "Observed carrier Doppler or frequency offset for a configured RF/link path.",
      owner: :comms,
      value_kind: :metric,
      value_type: :float,
      unit: "Hz",
      primary_scope: :link,
      optional_scopes: [:spacecraft, :contact, :ground_station, :source_endpoint, :transport],
      product: :link_rf,
      storage: :adapter
    },
    %{
      observable_id: "contacts.phase",
      name: "Contact phase",
      description: "Current lifecycle phase for a scheduled or realized contact.",
      owner: :contacts,
      value_kind: :state,
      value_type: :enum,
      enum_values: [:scheduled, :active, :completed, :stopped, :expired, :canceled, :unknown],
      primary_scope: :contact,
      optional_scopes: [:mission, :spacecraft, :ground_station, :source_endpoint],
      product: :contacts,
      storage: :projection,
      state_color_policy: :contact_phase
    },
    %{
      observable_id: "commanding.queue_depth",
      name: "Command queue depth",
      description: "Number of commands pending dispatch for the selected mission context.",
      owner: :commanding,
      value_kind: :metric,
      value_type: :integer,
      unit: "commands",
      primary_scope: :mission,
      optional_scopes: [:spacecraft, :contact, :source_endpoint],
      product: :commanding,
      storage: :projection
    },
    %{
      observable_id: "runtime.managed_activity",
      name: "Managed runtime activity",
      description:
        "Managed capability action, timer, and record handling events emitted during runtime or replay.",
      owner: :runtime,
      value_kind: :state,
      value_type: :enum,
      enum_values: [
        :managed_capability_initialized,
        :managed_capability_record_handled,
        :managed_capability_timer_handled,
        :managed_action_requested,
        :managed_timer_scheduled,
        :managed_timer_fired,
        :managed_timer_canceled
      ],
      primary_scope: :mission,
      optional_scopes: [:spacecraft],
      product: :runtime_managed,
      storage: :projection,
      state_color_policy: :managed_runtime_activity
    },
    %{
      observable_id: "runtime.transport_activity",
      name: "Transport runtime activity",
      description:
        "Transport capability action, timer, and record handling events emitted during runtime or replay.",
      owner: :runtime,
      value_kind: :state,
      value_type: :enum,
      enum_values: [
        :transport_initialized,
        :transport_event_handled,
        :transport_control_input_handled,
        :transport_timer_handled,
        :transport_action_requested,
        :transport_timer_scheduled,
        :transport_timer_fired,
        :transport_timer_canceled
      ],
      primary_scope: :mission,
      optional_scopes: [:contact, :source_endpoint, :transport, :link],
      product: :runtime_transport,
      storage: :projection,
      state_color_policy: :transport_runtime_activity
    },
    %{
      observable_id: "ingress.processing_latency_ms",
      name: "Ingress processing latency",
      description: "Observed latency from ingress receipt to durable processing completion.",
      owner: :runtime,
      value_kind: :metric,
      value_type: :float,
      unit: "ms",
      primary_scope: :source_endpoint,
      optional_scopes: [:mission, :spacecraft, :contact, :transport],
      product: :runtime_ingress,
      storage: :runtime_stream
    }
  ]

  @ids MapSet.new(Enum.map(@definition_attrs, & &1.observable_id))

  @spec list() :: [t()]
  def list do
    Enum.map(@definition_attrs, &struct!(__MODULE__, &1))
  end

  @spec ids() :: [binary()]
  def ids, do: Enum.map(@definition_attrs, & &1.observable_id)

  @spec fetch(binary()) :: {:ok, t()} | {:error, :unknown_operational_observable}
  def fetch(observable_id) when is_binary(observable_id) do
    case Enum.find(@definition_attrs, &(&1.observable_id == observable_id)) do
      definition when is_map(definition) -> {:ok, struct!(__MODULE__, definition)}
      nil -> {:error, :unknown_operational_observable}
    end
  end

  @spec known?(term()) :: boolean()
  def known?(observable_id) when is_binary(observable_id), do: MapSet.member?(@ids, observable_id)
  def known?(_observable_id), do: false

  @spec metadata() :: map()
  def metadata do
    %{
      registry_version: 1,
      observable_ids: ids(),
      backed_observable_ids: backed_ids(),
      definitions: Enum.map(list(), &to_map/1)
    }
  end

  @spec backed_ids() :: [binary()]
  def backed_ids do
    [
      "comms.transport.downlink_bitrate",
      "comms.transport.uplink_bitrate",
      "comms.transport.execution_state",
      "comms.transport.connection_state",
      "ground.station.connection_state",
      "ground.station.antenna_pointing_state",
      "link.rf_lock_state",
      "link.frame_sync_state",
      "link.snr_db",
      "link.eb_n0_db",
      "link.symbol_rate_sps",
      "link.doppler_hz",
      "contacts.phase",
      "commanding.queue_depth",
      "runtime.managed_activity",
      "runtime.transport_activity",
      "ingress.processing_latency_ms"
    ]
  end

  @spec backed?(term()) :: boolean()
  def backed?(observable_id) when is_binary(observable_id), do: observable_id in backed_ids()
  def backed?(_observable_id), do: false

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = definition) do
    definition
    |> Map.from_struct()
    |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
    |> Map.new()
  end
end
