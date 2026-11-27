Code.require_file("rest_client.exs", __DIR__)

defmodule EarendilOrbits do
  @moduledoc """
  Gives every applied Earendil spacecraft an orbit through the public element-set API (#889):
  one bulk `POST /missions/:id/element-sets` per 1,000 spacecraft, never the database.

  The orbits are synthetic LEO, as the pass-prediction benchmark's fleet is: 500–600 km, half at
  53° and half sun-synchronous at 97.6°, with RAAN and mean anomaly spread by the golden angle so
  the fleet covers the sky. Each spacecraft's elements come from its SCID only, with the epoch at
  the start of today (UTC), so a re-run on the same day stores nothing (`unchanged`) and a run on a
  later day gives every craft a newer current set.
  """

  import EarendilRestClient, only: [request!: 4, request_envelope!: 3]

  @mu_km3_s2 398_600.4418
  @earth_radius_km 6378.137
  @golden_angle 137.507764
  @batch 1_000
  @names_page 500

  def seed(client, mission_id) do
    {client, craft} = spacecraft(client, mission_id, nil, [])
    epoch = Date.utc_today() |> DateTime.new!(~T[00:00:00.000000], "Etc/UTC")

    if craft == [] do
      IO.puts("  orbits wait on an applied fleet")
      client
    else
      craft
      |> Enum.chunk_every(@batch)
      |> Enum.reduce(client, &post_batch(&2, mission_id, &1, epoch))
    end
  end

  defp post_batch(client, mission_id, batch, epoch) do
    items = Enum.map(batch, &item(&1, epoch))

    {client, %{"counts" => counts}} =
      request!(client, :post, "/missions/#{mission_id}/element-sets", %{element_sets: items})

    if counts["refused"] > 0, do: raise("orbits: #{counts["refused"]} element sets refused")

    IO.puts(
      "  orbits: #{counts["created"]} stored, #{counts["unchanged"]} already current (epoch #{DateTime.to_date(epoch)})"
    )

    client
  end

  defp spacecraft(client, mission_id, cursor, acc) do
    query =
      URI.encode_query(Enum.reject([limit: @names_page, cursor: cursor], &is_nil(elem(&1, 1))))

    {client, body} =
      request_envelope!(client, :get, "/missions/#{mission_id}/spacecraft/names?#{query}")

    acc = acc ++ Enum.filter(body["data"]["names"], &is_integer(&1["scid"]))

    case body["meta"]["next_cursor"] do
      nil -> {client, acc}
      next -> spacecraft(client, mission_id, next, acc)
    end
  end

  @doc "The bulk item for one spacecraft `{id, name, scid}` at `epoch`."
  def item(%{"id" => id, "name" => name, "scid" => scid}, epoch) do
    altitude = 500.0 + rem(scid * 37, 101)
    a = @earth_radius_km + altitude
    mean_motion = 86_400.0 / (2 * :math.pi() * :math.sqrt(a * a * a / @mu_km3_s2))

    %{
      spacecraft_id: id,
      omm: %{
        "OBJECT_NAME" => name,
        "NORAD_CAT_ID" => 90_000 + scid,
        "MEAN_ELEMENT_THEORY" => "SGP4",
        "EPOCH" => epoch |> DateTime.to_naive() |> NaiveDateTime.to_iso8601(),
        "MEAN_MOTION" => Float.round(mean_motion, 8),
        "ECCENTRICITY" => 0.0005,
        "INCLINATION" => if(rem(scid, 2) == 0, do: 53.0, else: 97.6),
        "RA_OF_ASC_NODE" => angle(scid * @golden_angle),
        "ARG_OF_PERICENTER" => 90.0,
        "MEAN_ANOMALY" => angle(scid * @golden_angle * 2.618),
        "BSTAR" => 2.0e-5,
        "MEAN_MOTION_DOT" => 0.0,
        "MEAN_MOTION_DDOT" => 0.0
      }
    }
  end

  defp angle(value), do: Float.round(:math.fmod(value, 360.0), 4)
end
