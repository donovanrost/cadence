defmodule Cadence.Runtime.RealizedContactRuntimeSpecTest do
  use ExUnit.Case, async: false

  alias Cadence.Runtime.Contacts, as: RuntimeContacts
  alias Cadence.Runtime.RealizedContactRuntimeSpec

  test "starts an exact realized Contact spec without Control or Repo" do
    assert Process.whereis(Cadence.Control.Supervisor) == nil
    assert Process.whereis(Cadence.Repo) == nil
    start_supervised!(Cadence.Runtime.Supervisor)

    mission_id = "isolated-contact-#{System.unique_integer([:positive])}"

    path =
      %{
        path_id: "downlink-primary",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: "endpoint-a"
      }

    assert {:ok, spec} =
             RealizedContactRuntimeSpec.new(%{
               runtime_spec_id: "contact-spec-1",
               generation: 3,
               realized_contact_id: "contact-a",
               mission_id: mission_id,
               source_endpoint_refs: ["endpoint-a"],
               contact_intents: [:telemetry_downlink],
               paths: [path],
               clock_mode: :live,
               metadata: %{"source" => "isolated-test"}
             })

    assert {:ok, _runtime} = RuntimeContacts.start(spec)

    assert {:ok, snapshot} = RuntimeContacts.snapshot(mission_id, "contact-a")
    assert snapshot.realized_contact_id == "contact-a"
    assert snapshot.path_count == 1
    assert hd(snapshot.paths).path_id == "downlink-primary"

    assert Process.whereis(Cadence.Control.Supervisor) == nil
    assert Process.whereis(Cadence.Repo) == nil
  end

  test "rejects a caller-claimed content hash that does not match the exact spec" do
    path =
      %{
        path_id: "downlink-primary",
        direction: :downlink,
        selection_role: :selected
      }

    assert {:error, :realized_contact_runtime_spec_hash_mismatch} =
             RealizedContactRuntimeSpec.new(%{
               runtime_spec_id: "contact-spec-invalid",
               generation: 1,
               content_sha256: String.duplicate("0", 64),
               realized_contact_id: "contact-invalid",
               mission_id: "mission-invalid",
               source_endpoint_refs: [],
               contact_intents: [],
               paths: [path],
               clock_mode: :live,
               metadata: %{}
             })
  end
end
