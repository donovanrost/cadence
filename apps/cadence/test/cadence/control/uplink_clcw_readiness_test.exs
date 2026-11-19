defmodule Cadence.Control.UplinkCLCWReadinessTest do
  @moduledoc """
  #38 / DECISIONS #59 follow-up: a qualified uplink reads ready only while its CLCW stream is
  live. One lost first report used to leave the FOP waiting all pass while readiness said ready.
  """
  use ExUnit.Case, async: false

  alias Cadence.Control.{UplinkQualification, UplinkReadiness}
  alias Cadence.Runtime.ProcessNamespace

  @key {"mission-clcw", "realized-clcw", "uplink-path", "gateway"}

  defmodule QualifyingSession do
    @moduledoc false
    # Qualifies on the first try; its gateway snapshot is whatever the test gives it.
    use GenServer
    def start_link(args), do: GenServer.start_link(__MODULE__, args)

    def init({registry, {m, c, p, b}, gateway_state}) do
      {:ok, _} = Registry.register(registry, {:transport_runtime, m, c, p, b}, nil)
      {:ok, %{mission: m, contact: c, gateway: gateway_state}}
    end

    def handle_call({:session_action, :review, []}, _from, state) do
      provider = %{
        adapter_key: :tcp_socket,
        peer: "127.0.0.1:50123",
        mission_id: state.mission,
        contact_id: state.contact
      }

      review = %{
        provider: provider,
        status: :blocked,
        pending_delivery_count: 0,
        incarnation: 1,
        basis_sha256: "basis"
      }

      {:reply, {:ok, review}, state}
    end

    def handle_call({:session_action, action, [_evidence]}, _from, state)
        when action in [:begin_recovery, :complete_recovery],
        do: {:reply, :ok, state}

    def handle_call(:snapshot, _from, state), do: {:reply, {:ok, %{state: state.gateway}}, state}
  end

  defmodule AttestingClient do
    @moduledoc false
    def attest_uplink_session(_context, _contact, _attrs, _opts),
      do: {:ok, %{"valid_until" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 240))}}
  end

  setup do
    table = :"uplink_clcw_readiness_#{System.unique_integer([:positive])}"
    registry = :"uplink_clcw_registry_#{System.unique_integer([:positive])}"
    start_supervised!({Registry, keys: :unique, name: registry})
    %{table: table, registry: registry}
  end

  test "readiness follows the CLCW stream: awaiting, none within the bound, live, stale", c do
    now = System.system_time(:millisecond)

    assert {:qualifying, :cop1_awaiting_clcw} =
             readiness(c, %{cop1_awaiting_clcw: true, cop1_started_at: now - 2_000})

    assert {:blocked, :cop1_no_clcw_report} =
             readiness(c, %{cop1_awaiting_clcw: true, cop1_started_at: now - 20_000})

    assert {:ready, nil} =
             readiness(c, %{cop1_awaiting_clcw: false, cop1_clcw_at: now - 1_000})

    assert {:qualifying, :cop1_clcw_stale} =
             readiness(c, %{cop1_awaiting_clcw: false, cop1_clcw_at: now - 20_000})
  end

  # Runs the driver once over a session whose gateway reports `gateway_state`.
  defp readiness(c, gateway_state) do
    session = start_supervised!({QualifyingSession, {c.registry, @key, gateway_state}})
    namespace = %ProcessNamespace{ProcessNamespace.default() | registry: c.registry}

    driver =
      start_supervised!(
        {UplinkQualification,
         process_namespace: namespace,
         readiness_table: c.table,
         tick_ms: nil,
         booking: fn _provider -> {:ok, booking()} end}
      )

    UplinkQualification.qualify_now(driver)

    %{"contact-clcw" => %{state: state, reason: reason}} =
      UplinkReadiness.for_contacts("org-clcw", "mission-clcw", ["contact-clcw"], c.table)

    stop_supervised!(UplinkQualification)
    stop_supervised!(QualifyingSession)
    _ = session
    {state, reason}
  end

  defp booking do
    now = DateTime.utc_now()

    %{
      organization_id: "org-clcw",
      mission_id: "mission-clcw",
      scheduled_contact_id: "contact-clcw",
      provider_reservation_id: "reservation-clcw",
      provider_contact_ref: "provider-contact-clcw",
      provider_id: "provider-clcw",
      spacecraft_id: "spacecraft-clcw",
      ground_station_ref: "station-clcw",
      starts_at: DateTime.add(now, -60),
      ends_at: DateTime.add(now, 540),
      client: AttestingClient,
      context: nil,
      call_opts: []
    }
  end
end
