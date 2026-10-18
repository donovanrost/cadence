defmodule Cadence.CommandHistoryFixtures do
  @moduledoc false
  alias Cadence.Dashboards.DataLinkResolverFixtures, as: DataFixtures
  alias Cadence.Reads.Telemetry
  alias Cadence.Repo
  alias Cadence.Runtime.TransportRecords
  alias Cadence.Telemetry.SampleRecords

  def sample!(c, value \\ 18_446_744_073_709_551_615) do
    binding = DataFixtures.persist_binding_set!(c.org, c.mission)
    DataFixtures.activate_binding_set!(c.org, c.mission, binding)
    DataFixtures.ingest!(c.mission, binding, "history-spacecraft", 42)
    sample = Telemetry.latest_value(c.org, c.mission, "HK.counter", [])
    # Ingress establishes valid packet/evidence references. The additional persisted
    # sample exercises historical JSON read fidelity, not unsigned64 wire encoding.
    {:ok, source} = SampleRecords.fetch_sample(c.org, c.mission, sample.sample_id)

    historical = %{
      source
      | sample_id: Cadence.Ids.new("sample"),
        raw_value: value,
        engineering_value: value,
        provenance: %{"secret" => "private-provenance"}
    }

    :ok = SampleRecords.persist_samples([historical])
    historical
  end

  def action!(c, id, request, release) do
    record =
      DataFixtures.transport_action_request(
        c.mission,
        id,
        "history-capability",
        :uplink,
        ~U[2026-09-10 08:04:00.000000Z],
        command_request_id: request,
        command_release_attempt_id: release,
        request_document: %{"secret" => "private-action"},
        metadata: %{"secret" => "private-action-metadata"}
      )

    {:ok, _} =
      Ecto.Multi.new()
      |> TransportRecords.add_action_request_inserts([record])
      |> Repo.transaction()

    record
  end

  def capability!(c, id, request, release, opts \\ []) do
    state =
      Keyword.get(opts, :state, %{
        "last_command_request_id" => request,
        "last_release_attempt_id" => release,
        "secret" => "private-state"
      })

    metadata =
      Keyword.get(opts, :metadata, %{
        "command_request_id" => "wrong-fallback",
        "command_release_attempt_id" => "wrong-fallback",
        "secret" => "private-capability-metadata"
      })

    record =
      DataFixtures.transport_capability_record(
        c.mission,
        id,
        "history-capability",
        :control_input_handled,
        ~U[2026-09-10 08:04:00.000000Z],
        state_snapshot: state,
        metadata: metadata
      )

    {:ok, _} =
      Ecto.Multi.new()
      |> TransportRecords.add_capability_record_inserts([record])
      |> Repo.transaction()

    record
  end
end
