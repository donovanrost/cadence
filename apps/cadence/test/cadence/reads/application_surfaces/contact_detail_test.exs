defmodule Cadence.Reads.ApplicationSurfaces.ContactDetailTest do
  use Cadence.DataCase, async: false
  alias Cadence.Applications.{ActionRequest, HostContext, SurfaceQueryRequest}
  alias Cadence.Applications.OpsConsole.Actions.ContactPlanning
  alias Cadence.ProviderChangeFixtures, as: Fixtures
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole

  @checker Path.expand(
             "../../../../../../frontend/modules/planning-and-contacts/src/features/contact-scheduling/decision-producer-check.mjs",
             __DIR__
           )

  setup do
    c = Fixtures.setup_contact()

    assert {:ok, _} =
             Fixtures.advance(c, 2, %{
               "starts_at" => Fixtures.shift(c.baseline["starts_at"], 60),
               "ends_at" => Fixtures.shift(c.baseline["ends_at"], 60)
             })

    c
  end

  test "the real producer renders native Vue evidence and approval returns the persisted receipt",
       c do
    model = props(c)
    assert model["detail"]["selected"]["review_complete"]
    assert model["detail"]["permissions"]["decide"]
    assert model["detail"]["selected"]["provider_revision"] == 2
    assert length(model["detail"]["changes"]["entries"]) == 1
    refute Jason.encode!(model) =~ "credential_ref"

    {output, status} =
      System.cmd("node", [@checker, Jason.encode!(model), "approve-provider-change"],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert [_, json] = Regex.run(~r/RESERVATION_PAYLOAD=(\{[^\n]+\})/, output)
    input = Jason.decode!(json)

    assert input["change_evidence"]["proposal_hash"] ==
             model["detail"]["selected"]["proposal_hash"]

    assert {:ok, %{"lifecycleState" => "approved"}} =
             ContactPlanning.execute(
               c.admin_scope,
               HostContext.mission(c.mission_id),
               "contact_detail",
               %ActionRequest{
                 application_key: "ops_console",
                 application_version: 1,
                 action_id: "approve-provider-change",
                 params: input
               }
             )

    refreshed = props(c)["detail"]
    assert refreshed["selected"]["lifecycle_state"] == "approved"
    assert [%{"action" => "provider_change.approved"}] = refreshed["audit"]["entries"]
  end

  test "selected historical evidence is independent of history paging and cannot cross reservations",
       c do
    old = props(c)["detail"]["selected"]

    assert {:ok, _} =
             Fixtures.advance(c, 3, %{
               "starts_at" => Fixtures.shift(c.baseline["starts_at"], 120),
               "ends_at" => Fixtures.shift(c.baseline["ends_at"], 120)
             })

    model = props(c, %{"change_id" => old["id"], "before_revision" => "2"})["detail"]
    assert model["reservation"]["provider_revision"] == 3
    assert model["selected"]["provider_revision"] == 2
    assert model["selected"]["proposal_hash"] == old["proposal_hash"]
    assert model["changes"]["entries"] == []

    for query <- [
          %{"change_id" => "foreign"},
          %{"before_audit" => "foreign"},
          %{"before_revision" => "01"},
          %{"before_revision" => "2147483648"},
          %{"unknown" => "value"}
        ] do
      assert {:error, :unsupported_application_surface_query} = load(c, query)
    end
  end

  test "operational extensions are reviewable while unrelated provider data stays restricted",
       c do
    assert {:ok, _} =
             Fixtures.advance(c, 3, %{
               "extensions" => %{
                 "cost" => 120,
                 "estimated_capacity" => %{"value" => 2000, "unit" => "bytes"},
                 "provider_change" => %{"deadline_at" => "2027-01-01T00:00:00Z"}
               }
             })

    selected = props(c)["detail"]["selected"]
    assert selected["review_complete"]

    assert Enum.any?(
             selected["fields"],
             &(&1["field"] == "extensions.cost" and &1["after"] == "120")
           )

    assert {:ok, _} =
             Fixtures.advance(c, 4, %{
               "extensions" => %{
                 "private_provider_document" => %{"private_value" => "never-render-this"}
               }
             })

    model = props(c)
    refute model["detail"]["selected"]["review_complete"]
    refute Jason.encode!(model) =~ "never-render-this"
    refute Jason.encode!(model) =~ "private_provider_document"
  end

  defp props(c, query \\ %{}) do
    assert {:ok,
            %{
              "data" => %{
                "presentation" => %{"component" => "OpsContactDetail", "props" => props}
              }
            }} = load(c, query)

    props
  end

  defp load(c, query),
    do:
      OpsConsole.load(c.admin_scope, HostContext.mission(c.mission_id), %SurfaceQueryRequest{
        application_key: "ops_console",
        application_version: 1,
        surface_id: "contact_detail",
        surface_version: 1,
        query_id: "cadence.ops.contact_detail",
        query_version: 1,
        params:
          Map.merge(%{"provider_reservation_id" => c.reservation.provider_reservation_id}, query)
      })
end
