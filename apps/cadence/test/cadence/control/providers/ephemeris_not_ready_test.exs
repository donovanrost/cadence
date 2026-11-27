defmodule Cadence.Control.Providers.EphemerisNotReadyTest do
  @moduledoc """
  Ephemeris readiness (#974): a pair the routing rules bind but with no ready route is recorded
  `not_ready` with the scheduling refusal, the reconcile doesn't stage it again while its basis is
  unchanged, and the retry sweep re-checks it hourly; when two transports pin versions of one
  provider, the run uses the highest READY one.
  """
  use Cadence.DataCase, async: false

  import Cadence.EphemerisUploadFixtures
  import Ecto.Query

  alias Cadence.Comms.{RoutingRule, RoutingRuleStore, Transport}
  alias Cadence.Control.Providers.EphemerisUploads
  alias Cadence.GroundNetworks.EphemerisStates
  alias Cadence.GroundNetworks.MissionProviders.ProviderRow, as: MissionProviderRow
  alias Cadence.Jobs
  alias Cadence.Management.Transports
  alias Cadence.Repo

  setup do
    setup_ephemeris()
  end

  test "a bound pair without a ready route is not_ready, isn't re-staged, and is re-checked",
       c do
    upload_provider!(c)
    validated!(c, c.provider.version, nil)
    {:ok, _results} = submit(c, norad: 25_544)
    clear_jobs!(c)

    # Bound by the rule, so the reconcile sees it pending once; the run records why it waits.
    assert EphemerisUploads.reconcile() == 1
    assert {:ok, %{"not_ready" => 1}} = run(c)
    refute_received {:uploaded, _ref, _ephemeris}
    clear_jobs!(c)

    assert %{status: "not_ready", reason: "mission_provider_not_validated", next_retry_at: at} =
             state(c)

    assert DateTime.diff(at, now(), :minute) == 60

    assert %{c.provider.provider_id => %{"not_ready" => 1}} ==
             EphemerisStates.buckets(c.org, c.mission)

    # Repeated sweeps stage nothing while the basis is unchanged and the re-check isn't due.
    assert EphemerisUploads.reconcile() == 0
    assert EphemerisUploads.reconcile() == 0
    assert EphemerisUploads.retry_due(now()) == 0
    assert Jobs.list_open_jobs(:ephemeris_upload, c.mission) == []

    # The route becomes ready; the hourly re-check stages it and the run uploads.
    validated!(c, c.provider.version, now())
    assert EphemerisUploads.retry_due(DateTime.add(now(), 3_600)) == 1

    assert [%{payload: %{"pairs" => [[sc, provider]]}}] =
             Jobs.list_open_jobs(:ephemeris_upload, c.mission)

    assert {sc, provider} == {c.sc, c.provider.provider_id}
    assert {:ok, %{"uploaded" => 1}} = run(c, pairs: [{sc, provider}])
    assert_received {:uploaded, "SIM-001", _ephemeris}

    assert %{status: "uploaded", next_retry_at: nil} = state(c)

    assert %{c.provider.provider_id => %{"uploaded" => 1}} ==
             EphemerisStates.buckets(c.org, c.mission)
  end

  test "a not_ready pair whose set changes is pending again (sent once ready)", c do
    upload_provider!(c)
    validated!(c, c.provider.version, nil)
    {:ok, _results} = submit(c, norad: 25_544)
    assert {:ok, %{"not_ready" => 1}} = run(c)

    {:ok, _results} = submit(c, norad: 25_544, hours_ago: 0)

    assert %{c.provider.provider_id => %{"pending" => 1}} ==
             EphemerisStates.buckets(c.org, c.mission)
  end

  test "with v2 pinned but not ready and v1 ready, the run uploads through v1 and settles", c do
    upload_provider!(c)
    v2 = c.provider.version + 1

    new_version!(c, Map.put(capabilities(), "orbit", %{"source" => "accepts_ephemeris_upload"}))
    pin_second_transport!(c, v2)
    validated!(c, v2, nil)

    {:ok, _results} = submit(c, norad: 25_544)
    clear_jobs!(c)

    assert {:ok, %{"uploaded" => 1}} = run(c)
    assert_received {:uploaded, "SIM-001", _ephemeris}

    # Uploaded through v1 while the rules bind v2: counted uploaded, never re-staged by the
    # reconcile, and re-checked hourly so it moves to v2 once v2's route is ready.
    assert %{
             status: "uploaded",
             provider_version: v1,
             bound_provider_version: ^v2,
             next_retry_at: %DateTime{}
           } = state(c)

    assert v1 == c.provider.version

    assert %{c.provider.provider_id => %{"uploaded" => 1}} ==
             EphemerisStates.buckets(c.org, c.mission)

    assert EphemerisUploads.reconcile() == 0
    assert EphemerisUploads.reconcile() == 0

    validated!(c, v2, now())
    assert EphemerisUploads.retry_due(DateTime.add(now(), 3_600)) == 1
    assert {:ok, %{"uploaded" => 1}} = run(c, pairs: [{c.sc, c.provider.provider_id}])
    assert_received {:uploaded, "SIM-001", _ephemeris}
    assert %{provider_version: ^v2, bound_provider_version: ^v2, next_retry_at: nil} = state(c)
  end

  test "lookup through a ready v1 while v2 uploads but isn't ready: re-checked, then uploaded",
       c do
    # v1 looks orbits up (the fixture's default capabilities); v2 accepts uploads.
    v2 = c.provider.version + 1
    new_version!(c, Map.put(capabilities(), "orbit", %{"source" => "accepts_ephemeris_upload"}))
    pin_second_transport!(c, v2)
    validated!(c, v2, nil)

    {:ok, _results} = submit(c, norad: 25_544)
    clear_jobs!(c)

    assert {:ok, %{"lookup" => 1}} = run(c)
    refute_received {:uploaded, _ref, _ephemeris}

    assert %{
             status: "lookup",
             provider_version: v1,
             bound_provider_version: ^v2,
             next_retry_at: %DateTime{}
           } = state(c)

    assert v1 == c.provider.version
    assert EphemerisUploads.reconcile() == 0

    validated!(c, v2, now())
    assert EphemerisUploads.retry_due(DateTime.add(now(), 3_600)) == 1
    assert {:ok, %{"uploaded" => 1}} = run(c, pairs: [{c.sc, c.provider.provider_id}])
    assert_received {:uploaded, "SIM-001", _ephemeris}
    assert %{status: "uploaded", provider_version: ^v2, next_retry_at: nil} = state(c)
  end

  test "an unready lookup pair with a new set is pending, not lookup, until the run decides", c do
    # The fixture's provider looks orbits up; its version isn't validated, so no route is ready.
    validated!(c, c.provider.version, nil)
    {:ok, _results} = submit(c, norad: 25_544)
    clear_jobs!(c)
    assert {:ok, _summary} = run(c)
    assert %{status: "not_ready"} = state(c)

    {:ok, _results} = submit(c, norad: 25_544, hours_ago: 0)

    assert %{c.provider.provider_id => %{"pending" => 1}} ==
             EphemerisStates.buckets(c.org, c.mission)
  end

  test "a not_ready reason names this provider's refusal, never another provider's" do
    findings = [
      %{code: :mission_provider_not_validated, resource_id: "rule-a"},
      %{code: :provider_delivery_profile_not_ready, resource_id: "rule-b"},
      %{code: :something_new, resource_id: "rule-d"}
    ]

    assert EphemerisUploads.refusal({:ok, %{findings: findings}}, ["rule-a"]) ==
             "mission_provider_not_validated"

    assert EphemerisUploads.refusal({:ok, %{findings: findings}}, ["rule-b"]) ==
             "provider_delivery_profile_not_ready"

    # A code outside the closed vocabulary (#972) reads as the generic reason.
    assert EphemerisUploads.refusal({:ok, %{findings: findings}}, ["rule-d"]) ==
             "no_ready_route"

    assert EphemerisUploads.refusal({:ok, %{findings: findings}}, ["rule-c"]) ==
             "no_ready_route"

    assert EphemerisUploads.refusal({:error, :spacecraft_not_found}, ["rule-a"]) ==
             "spacecraft_not_found"
  end

  test "the buckets add up with not_ready among them", c do
    upload_provider!(c)
    second = second_bound_spacecraft!(c)
    {:ok, _results} = submit(c, norad: 25_544)
    {:ok, _results} = submit(%{c | sc: second}, norad: 25_545)

    assert {:ok, %{"uploaded" => 2}} =
             EphemerisUploads.run(c.org, c.mission, [c.sc, second],
               now: now(),
               client: Cadence.EphemerisUploadFixtures.UploadClient,
               test_pid: self()
             )

    validated!(c, c.provider.version, nil)
    {:ok, _results} = submit(%{c | sc: second}, norad: 25_545, hours_ago: 0)
    assert {:ok, %{"not_ready" => 1}} = run(%{c | sc: second})

    buckets = EphemerisStates.buckets(c.org, c.mission)[c.provider.provider_id]
    assert buckets == %{"uploaded" => 1, "not_ready" => 1}
    assert buckets |> Map.values() |> Enum.sum() == 2
  end

  defp validated!(c, version, at) do
    {1, _rows} =
      from(row in MissionProviderRow,
        where:
          row.organization_id == ^c.org and row.mission_id == ^c.mission and
            row.provider_id == ^c.provider.provider_id and row.version == ^version
      )
      |> Repo.update_all(set: [last_validated_at: at])
  end

  # A second transport pinning `version`, bound to the fixture spacecraft by its own rule.
  defp pin_second_transport!(c, version) do
    {:ok, transport} =
      Transports.persist_transport(
        c.org,
        Transport.new(%{
          transport_id: c.transport.transport_id <> "-v#{version}",
          mission_id: c.mission,
          display_name: "Simulator telemetry ingress v#{version}",
          origin: :provider_managed,
          mission_provider_id: c.provider.provider_id,
          mission_provider_version: version,
          service_profile_ref: c.transport.service_profile_ref,
          delivery_profile_ref: c.transport.delivery_profile_ref
        })
      )

    {:ok, _rule} =
      RoutingRuleStore.create_routing_rule(
        c.org,
        RoutingRule.new(%{
          routing_rule_id: "rule-v#{version}-" <> c.sc,
          mission_id: c.mission,
          spacecraft_id: c.sc,
          display_name: "Downlink through v#{version}",
          purpose_label: "Telemetry",
          direction: :inbound,
          transport_id: transport.transport_id,
          transport_version: transport.version,
          role: :candidate
        })
      )
  end
end
