defmodule CadenceWeb.Console.ProviderEphemerisAPITest do
  @moduledoc """
  `GET /api/v1/missions/:mission_id/providers/:provider_id/ephemeris/spacecraft` (#972): the
  spacecraft of a `provider_ephemeris` group, named with their SCIDs and paged; and the mission
  channel's `providers` read-update resource.
  """
  use CadenceWeb.ConnCase, async: false

  import Cadence.EphemerisUploadFixtures

  alias CadenceWeb.Console.MissionChannel
  alias CadenceWeb.TestFixtures

  setup do
    c = setup_ephemeris()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, c.scope.organization, role: :member)

    path =
      "/api/v1/missions/#{c.mission}/providers/#{c.provider.provider_id}/ephemeris/spacecraft"

    Map.merge(c, %{user: user, path: path})
  end

  test "a group's spacecraft are named, with SCID and the recorded outcome, and paged", c do
    {:ok, _results} = submit(c, [])
    clear_jobs!(c)
    {:ok, %{"norad_id_missing" => 1}} = run(c)

    assert %{"data" => [row], "meta" => %{"next_cursor" => nil}} =
             c |> get_page(%{"cause" => "norad_id_missing"}) |> json_response(200)

    assert %{
             "spacecraft" => %{"id" => id, "name" => name, "scid" => scid},
             "reason" => nil,
             "attempts" => 0,
             "next_retry_at" => nil,
             "since" => since
           } = row

    assert id == c.sc
    assert {name, scid} == {c.spacecraft.display_name, c.spacecraft.scid}
    assert is_binary(since)

    assert %{"data" => []} =
             c |> get_page(%{"cause" => "failed"}) |> json_response(200)
  end

  test "an unknown cause or limit is refused by name; an unknown provider is 404", c do
    assert %{"error" => %{"code" => "invalid_params", "details" => %{"field" => "cause"}}} =
             c |> get_page(%{"cause" => "lookup"}) |> json_response(422)

    assert %{"error" => %{"details" => %{"field" => "limit"}}} =
             c |> get_page(%{"cause" => "failed", "limit" => "0"}) |> json_response(422)

    assert %{"error" => %{"code" => "provider_not_found"}} =
             c.user
             |> TestFixtures.member_conn()
             |> get(String.replace(c.path, c.provider.provider_id, "provider-none"), %{
               "cause" => "failed"
             })
             |> json_response(404)
  end

  test "the mission channel carries a providers read-update resource" do
    resources = MissionChannel.read_update_resources()
    assert resources[:providers_changed] == "providers"
  end

  defp get_page(c, params), do: c.user |> TestFixtures.member_conn() |> get(c.path, params)
end
