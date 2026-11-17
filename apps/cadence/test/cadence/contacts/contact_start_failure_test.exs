defmodule Cadence.Contacts.ContactStartFailureTest do
  @moduledoc "ux U45: a failed contact start is classified into one of its worded reason keys."
  use Cadence.UnitCase, async: true

  alias Cadence.Contacts.{ContactStartFailure, RealizedContact}

  @at ~U[2026-11-14 00:34:00.839000Z]

  test "the runtime's nested start errors map to the U45 keys" do
    listen = fn reason -> {:tcp_provider_listen_failed, "provider_profile_3F", reason} end

    cases = [
      {wrap(listen.(:eaddrinuse)), {"listener_in_use", "provider_profile_3F"}},
      {wrap(listen.(:eacces)), {"listener_unavailable", "provider_profile_3F"}},
      {wrap({:tcp_provider_connect_failed, "p", :econnrefused}), {"connect_failed", "p"}},
      {:no_active_binding_set, {"no_runtime_spec", nil}},
      {{:mission_runtime_spec_mismatch, :binding_set_identity}, {"no_runtime_spec", nil}},
      {{:shutdown, {:failed_to_start_child, Cadence.Runtime.TransportRuntime, :boom}},
       {"uplink_session_failed", nil}},
      {{:shutdown, {:failed_to_start_child, Cadence.Runtime.IngressPersistenceProjector, :boom}},
       {"ingress_pipeline_failed", nil}},
      {{:listen_endpoint_claimed, %{port: 5012, provider_binding_id: "b"}},
       {"listen_endpoint_claimed", "b"}},
      {:something_else, {"unknown", nil}}
    ]

    for {error, expected} <- cases, do: assert(ContactStartFailure.classify(error) == expected)

    assert Enum.sort(ContactStartFailure.reasons()) ==
             Enum.sort(~w(listener_in_use listener_unavailable connect_failed
                          ingress_pipeline_failed uplink_session_failed no_runtime_spec
                          listen_endpoint_claimed unknown))
  end

  test "attempts count up from the first failure, and a start closes the failure" do
    contact = contact(%{})
    first = ContactStartFailure.failed(contact, wrap(:eaddrinuse), @at)

    assert %{"attempts" => 1, "first_failed_at" => at, "last_attempt_at" => at} =
             first["start_failure"]

    later = DateTime.add(@at, 10)
    second = ContactStartFailure.failed(contact(first), wrap(:eaddrinuse), later)
    assert %{"attempts" => 2, "first_failed_at" => ^at} = second["start_failure"]
    assert second["start_failure"]["last_attempt_at"] == DateTime.to_iso8601(later)

    assert %{"start_failure" => %{"started_at" => _started}} =
             ContactStartFailure.started(contact(second), later)

    assert ContactStartFailure.started(contact(%{}), later) == %{}
    assert ContactStartFailure.open_failure(contact(%{})) == nil
  end

  test "U91: no_runtime_spec says whether the mission has no configuration or Cadence can't verify it" do
    detail = fn error ->
      ContactStartFailure.failed(contact(%{}), error, @at)["start_failure"]
      |> Map.take(["reason", "reason_detail"])
    end

    assert %{"reason" => "no_runtime_spec", "reason_detail" => "no_configuration"} =
             detail.({:error, :no_active_binding_set})

    assert %{"reason" => "no_runtime_spec", "reason_detail" => "configuration_unverifiable"} =
             detail.({:error, {:mission_runtime_spec_mismatch, :binding_set_content_sha256}})

    assert detail.(wrap(:eaddrinuse)) |> Map.has_key?("reason_detail") == false
  end

  test "the stored failure message is bounded" do
    huge = {:error, String.duplicate("x", 5_000)}

    %{"start_failure" => %{"failure_message" => message}} =
      ContactStartFailure.failed(contact(%{}), huge, @at)

    assert String.length(message) <= 300
  end

  defp wrap(cause),
    do: {:shutdown, {:failed_to_start_child, Cadence.Runtime.PathCoordinator, cause}}

  defp contact(metadata),
    do:
      RealizedContact.new(%{
        realized_contact_id: "run",
        mission_id: "mission",
        scheduled_contact_id: "scheduled",
        source_endpoint_refs: [],
        paths: [],
        metadata: metadata
      })
end
