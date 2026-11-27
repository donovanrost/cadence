defmodule CadenceSimulator.Provider.EphemerisTest do
  @moduledoc """
  The simulated provider's ephemeris upload (#968): it declares that it accepts uploads, stores
  one per spacecraft idempotently per content hash, and a scenario reading orbit readiness from
  uploads is ready only for a spacecraft with a fresh one.
  """
  use CadenceSimulator.Case, async: false

  @moduletag :config

  alias CadenceSimulator.Provider
  alias CadenceSimulator.Provider.{Ephemeris, OrbitReadiness, Router, Store}
  alias Plug.Conn
  alias Plug.Test

  @router_options [
    provider_auth: [
      provider_admin_api_token: "admin-secret",
      provider_api_token: "provider-secret"
    ]
  ]

  setup do
    :ok = Store.clear()

    {:ok, scenario} =
      Provider.create_scenario(%{
        "spacecraft_count" => 2,
        "spacecraft_prefix" => "EARENDIL",
        "orbit_readiness" => %{"source_kind" => "uploaded"}
      })

    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 7})
    %{run: run, env: run["provider_environment_ref"]}
  end

  test "declares that it accepts ephemeris uploads", c do
    conn = request(:get, "/provider/v1/capabilities", c.env)
    assert %{"data" => %{"orbit" => %{"source" => "accepts_ephemeris_upload"}}} = decode(conn)
  end

  test "stores an upload per spacecraft, idempotently per content hash", c do
    first = request(:put, "/provider/v1/spacecraft/EARENDIL-001/ephemeris", c.env, upload("a"))
    assert first.status == 201

    assert %{"data" => %{"spacecraft_ref" => "EARENDIL-001", "content_sha256" => sha}} =
             decode(first)

    assert sha == sha("a")

    again = request(:put, "/provider/v1/spacecraft/EARENDIL-001/ephemeris", c.env, upload("a"))
    assert again.status == 200

    newer = request(:put, "/provider/v1/spacecraft/EARENDIL-001/ephemeris", c.env, upload("b"))
    assert newer.status == 201

    read = request(:get, "/provider/v1/spacecraft/EARENDIL-001/ephemeris", c.env)
    assert %{"data" => %{"content_sha256" => latest}} = decode(read)
    assert latest == sha("b")
  end

  test "refuses an unknown spacecraft and a malformed upload", c do
    unknown = request(:put, "/provider/v1/spacecraft/EARENDIL-009/ephemeris", c.env, upload("a"))
    assert unknown.status == 404

    bad = Map.put(upload("a"), "omm", %{"EPOCH" => "2026-11-27T00:00:00"})
    malformed = request(:put, "/provider/v1/spacecraft/EARENDIL-001/ephemeris", c.env, bad)
    assert malformed.status == 422
    assert %{"error" => %{"code" => "invalid_request", "detail" => detail}} = decode(malformed)
    assert detail =~ "MEAN_MOTION"

    no_upload = request(:get, "/provider/v1/spacecraft/EARENDIL-002/ephemeris", c.env)
    assert no_upload.status == 404
  end

  test "refuses non-physical or non-numeric elements, and readiness stays missing", c do
    for {key, value} <- [
          {"MEAN_MOTION", nil},
          {"MEAN_MOTION", "15.2"},
          {"MEAN_MOTION", 0},
          {"ECCENTRICITY", 1.0},
          {"INCLINATION", 181.0},
          {"MEAN_ANOMALY", -1.0}
        ] do
      bad = put_in(upload("a"), ["omm", key], value)
      refused = request(:put, "/provider/v1/spacecraft/EARENDIL-001/ephemeris", c.env, bad)
      assert refused.status == 422
      assert %{"error" => %{"detail" => detail}} = decode(refused)
      assert detail =~ key
    end

    params = %{"spacecraft_refs" => ["EARENDIL-001"], "starts_at" => iso(DateTime.utc_now())}

    assert {:error, {:orbit_not_ready, %{"status" => "missing"}}} =
             OrbitReadiness.for_search(c.run, params)
  end

  test "refuses an OMM whose EPOCH isn't the upload's epoch", c do
    shifted = put_in(upload("a"), ["omm", "EPOCH"], "2026-11-27T00:00:00.000001")
    refused = request(:put, "/provider/v1/spacecraft/EARENDIL-001/ephemeris", c.env, shifted)
    assert refused.status == 422

    assert %{"error" => %{"detail" => "ephemeris.omm.EPOCH must equal ephemeris.epoch"}} =
             decode(refused)

    # The same instant, written without the Z and with microseconds, is accepted.
    same = put_in(upload("a"), ["omm", "EPOCH"], "2026-11-27T00:00:00.000000")

    assert request(:put, "/provider/v1/spacecraft/EARENDIL-001/ephemeris", c.env, same).status ==
             201
  end

  test "refuses an orbit readiness source_kind other than synthetic or uploaded" do
    assert {:error, {:invalid, "orbit_readiness.source_kind must be synthetic or uploaded"}} =
             Provider.create_scenario(%{
               "spacecraft_count" => 1,
               "orbit_readiness" => %{"source_kind" => "uplaoded"}
             })
  end

  test "uploaded orbit readiness: missing, current, then expired", c do
    starts_at = DateTime.utc_now()
    params = %{"spacecraft_refs" => ["EARENDIL-001"], "starts_at" => iso(starts_at)}

    assert {:error, {:orbit_not_ready, %{"status" => "missing", "source_kind" => "uploaded"}}} =
             OrbitReadiness.for_search(c.run, params)

    epoch = DateTime.add(starts_at, -3600)
    {:ok, _upload, :created} = Ephemeris.put(c.run, "EARENDIL-001", upload("a", epoch))

    assert {:ok, %{"status" => "current", "ephemeris_ref" => ref, "valid_until" => until}} =
             OrbitReadiness.for_search(c.run, params)

    assert ref == sha("a")
    assert until == iso(DateTime.add(epoch, Ephemeris.max_age_seconds()))

    later = DateTime.add(epoch, Ephemeris.max_age_seconds() + 60)

    assert {:error, {:orbit_not_ready, %{"status" => "expired"}}} =
             OrbitReadiness.for_search(c.run, %{params | "starts_at" => iso(later)})

    both = %{params | "spacecraft_refs" => ["EARENDIL-001", "EARENDIL-002"]}

    assert {:error, {:orbit_not_ready, %{"status" => "missing", "ephemeris_ref" => nil}}} =
             OrbitReadiness.for_search(c.run, both)
  end

  test "a synthetic scenario keeps its configured readiness and ignores uploads" do
    {:ok, scenario} = Provider.create_scenario(%{"spacecraft_count" => 1})
    {:ok, run} = Provider.create_run(scenario["id"], %{"seed" => 1})

    assert {:ok, %{"status" => "current", "source_kind" => "synthetic"}} =
             OrbitReadiness.for_search(run, %{"spacecraft_refs" => ["SC-001"]})
  end

  defp upload(tag, epoch \\ ~U[2026-11-27 00:00:00Z]) do
    %{
      "omm" => %{
        "OBJECT_NAME" => "EARENDIL 1 #{tag}",
        "EPOCH" => iso(epoch),
        "MEAN_MOTION" => 15.2,
        "ECCENTRICITY" => 0.0005,
        "INCLINATION" => 53.0,
        "RA_OF_ASC_NODE" => 10.0,
        "ARG_OF_PERICENTER" => 20.0,
        "MEAN_ANOMALY" => 30.0,
        "BSTAR" => 2.0e-5
      },
      "epoch" => iso(epoch),
      "content_sha256" => sha(tag)
    }
  end

  defp sha(tag), do: :sha256 |> :crypto.hash(tag) |> Base.encode16(case: :lower)
  defp iso(at), do: DateTime.to_iso8601(at)

  defp request(method, path, env, body \\ nil) do
    conn =
      if body,
        do:
          method
          |> Test.conn(path, Jason.encode!(body))
          |> Conn.put_req_header("content-type", "application/json"),
        else: Test.conn(method, path)

    conn
    |> Conn.put_req_header("authorization", "Bearer provider-secret")
    |> Conn.put_req_header("x-simulator-environment-ref", env)
    |> Router.call(@router_options)
  end

  defp decode(conn), do: Jason.decode!(conn.resp_body)
end
