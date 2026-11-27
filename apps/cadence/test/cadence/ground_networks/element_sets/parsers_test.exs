defmodule Cadence.GroundNetworks.ElementSets.ParsersTest do
  use ExUnit.Case, async: true

  alias Cadence.GroundNetworks.ElementSets
  alias Cadence.GroundNetworks.ElementSets.{Elements, Omm, Tle}

  # ISS (ZARYA), element set 292 of 2008-09-20 (the TLE format's documented example).
  @title "ISS (ZARYA)"
  @line1 "1 25544U 98067A   08264.51782528 -.00002182  00000-0 -11606-4 0  2927"
  @line2 "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.72125391563537"
  @tle Enum.join([@title, @line1, @line2], "\n")

  # The same element set as CelesTrak's OMM JSON gives it.
  @omm %{
    "OBJECT_NAME" => "ISS (ZARYA)",
    "OBJECT_ID" => "1998-067A",
    "EPOCH" => "2008-09-20T12:25:40.104192",
    "MEAN_MOTION" => 15.72125391,
    "ECCENTRICITY" => 0.0006703,
    "INCLINATION" => 51.6416,
    "RA_OF_ASC_NODE" => 247.4627,
    "ARG_OF_PERICENTER" => 130.536,
    "MEAN_ANOMALY" => 325.0288,
    "EPHEMERIS_TYPE" => 0,
    "CLASSIFICATION_TYPE" => "U",
    "NORAD_CAT_ID" => 25_544,
    "ELEMENT_SET_NO" => 292,
    "REV_AT_EPOCH" => 56_353,
    "BSTAR" => -1.1606e-5,
    "MEAN_MOTION_DOT" => -2.182e-5,
    "MEAN_MOTION_DDOT" => 0
  }

  @kvn """
  CCSDS_OMM_VERS = 2.0
  COMMENT generated for the test
  CREATION_DATE = 2008-09-20T13:00:00
  ORIGINATOR = TEST
  OBJECT_NAME = ISS (ZARYA)
  OBJECT_ID = 1998-067A
  CENTER_NAME = EARTH
  REF_FRAME = TEME
  TIME_SYSTEM = UTC
  MEAN_ELEMENT_THEORY = SGP4
  EPOCH = 2008-264T12:25:40.104192
  MEAN_MOTION = 15.72125391 [rev/day]
  ECCENTRICITY = 0.0006703
  INCLINATION = 51.6416 [deg]
  RA_OF_ASC_NODE = 247.4627 [deg]
  ARG_OF_PERICENTER = 130.5360 [deg]
  MEAN_ANOMALY = 325.0288 [deg]
  NORAD_CAT_ID = 25544
  ELEMENT_SET_NO = 292
  BSTAR = -0.11606E-4
  MEAN_MOTION_DOT = -0.00002182
  MEAN_MOTION_DDOT = 0.0
  """

  @now ~U[2008-09-21 00:00:00.000000Z]
  @epoch ~U[2008-09-20 12:25:40.104192Z]

  describe "TLE" do
    test "reads every field of a three-line set" do
      assert {:ok, %Elements{} = e} = Tle.parse(@tle)

      assert %{
               format: :tle,
               object_name: "ISS (ZARYA)",
               norad_id: 25_544,
               element_set_number: 292,
               epoch: @epoch,
               inclination_deg: 51.6416,
               raan_deg: 247.4627,
               eccentricity: 0.0006703,
               arg_perigee_deg: 130.536,
               mean_anomaly_deg: 325.0288,
               mean_motion: 15.72125391,
               mean_motion_dot: -2.182e-5,
               mean_motion_ddot: +0.0
             } = e

      assert_in_delta e.bstar, -1.1606e-5, 1.0e-12
    end

    test "is the same set with or without its title, CRLF line ends or trailing blanks" do
      {:ok, two} = Tle.parse(@line1 <> "\r\n" <> @line2 <> "  \r\n")
      {:ok, plain} = Tle.parse(@line1 <> "\n" <> @line2)
      assert two.raw == plain.raw
      assert Elements.content_sha256(two) == Elements.content_sha256(plain)
      assert two.object_name == nil

      assert {:ok, %{object_name: "ISS (ZARYA)"}} =
               Tle.parse("0 ISS (ZARYA)\n#{@line1}\n#{@line2}")
    end

    test "refuses a checksum that doesn't match the line's digits" do
      broken = String.replace(@line1, "2927", "2928")

      assert {:error, {:bad_checksum, %{field: "line1", expected: 7}}} =
               Tle.parse(broken <> "\n" <> @line2)
    end

    test "refuses mismatched catalog numbers, wrong line numbers and short lines" do
      line2 = "2 25545" <> binary_part(@line2, 7, 61)
      line2 = line2 <> Integer.to_string(checksum(line2))

      assert {:error, {:catalog_number_mismatch, %{line1: 25_544, line2: 25_545}}} =
               Tle.parse(@line1 <> "\n" <> line2)

      assert {:error, {:unparseable, %{field: "line1"}}} = Tle.parse(@line2 <> "\n" <> @line2)
      assert {:error, {:unparseable, %{field: "line2"}}} = Tle.parse(@line1 <> "\n2 25544")
      assert {:error, {:unparseable, %{field: "tle"}}} = Tle.parse(@line1)
    end

    test "reads an Alpha-5 catalog number" do
      line1 = "1 A0001" <> binary_part(@line1, 7, 61)
      line2 = "2 A0001" <> binary_part(@line2, 7, 61)
      line1 = line1 <> Integer.to_string(checksum(line1))
      line2 = line2 <> Integer.to_string(checksum(line2))
      assert {:ok, %{norad_id: 100_001}} = Tle.parse(line1 <> "\n" <> line2)
    end
  end

  describe "OMM" do
    test "JSON and KVN give the same elements as the TLE" do
      {:ok, tle} = Tle.parse(@tle)

      for omm <- [@omm, @kvn] do
        assert {:ok, %Elements{format: :omm} = e} = Omm.parse(omm)

        for field <- ~w(epoch norad_id element_set_number object_name inclination_deg raan_deg
                        eccentricity arg_perigee_deg mean_anomaly_deg mean_motion)a,
            do: assert(Map.fetch!(e, field) == Map.fetch!(tle, field), "#{field}")

        for field <- ~w(bstar mean_motion_dot mean_motion_ddot)a,
            do: assert_in_delta(Map.fetch!(e, field), Map.fetch!(tle, field), 1.0e-12)
      end
    end

    test "takes Space-Track's numeric strings and hashes the same object the same way" do
      strings = Map.new(@omm, fn {key, value} -> {key, to_string(value)} end)
      assert {:ok, %{mean_motion: 15.72125391, norad_id: 25_544}} = Omm.parse(strings)

      reordered = @omm |> Enum.reverse() |> Map.new()
      {:ok, a} = Omm.parse(@omm)
      {:ok, b} = Omm.parse(reordered)
      assert a.raw == b.raw
    end

    test "refuses a missing element, a non-number and a theory other than SGP4" do
      assert {:error, {:unparseable, %{field: "BSTAR"}}} = Omm.parse(Map.delete(@omm, "BSTAR"))

      assert {:error, {:unparseable, %{field: "INCLINATION"}}} =
               Omm.parse(%{@omm | "INCLINATION" => "high"})

      assert {:error, {:unsupported_mean_element_theory, _}} =
               Omm.parse(Map.put(@omm, "MEAN_ELEMENT_THEORY", "DSST"))

      assert {:error, {:unparseable, %{field: "EPOCH"}}} =
               Omm.parse(%{@omm | "EPOCH" => "yesterday"})

      assert {:error, {:unparseable, %{field: "omm"}}} = Omm.parse("not kvn")
    end

    test "accepts Earth, TEME and UTC when supplied and refuses any other reference" do
      earth =
        Map.merge(@omm, %{"CENTER_NAME" => "earth", "REF_FRAME" => "TEME", "TIME_SYSTEM" => "UTC"})

      assert {:ok, _} = Omm.parse(earth)

      for {key, value, expected} <- [
            {"TIME_SYSTEM", "TAI", "UTC"},
            {"REF_FRAME", "EME2000", "TEME"},
            {"CENTER_NAME", "MARS", "EARTH"}
          ] do
        assert {:error, {:unsupported_reference, %{field: ^key, expected: ^expected}}} =
                 Omm.parse(Map.put(earth, key, value))

        kvn = String.replace(@kvn, ~r/^#{key} = .*$/m, "#{key} = #{value}")
        assert {:error, {:unsupported_reference, %{field: ^key}}} = Omm.parse(kvn)
      end
    end

    test "refuses a JSON integer too large to be an element instead of raising" do
      huge = String.to_integer(String.duplicate("9", 400))

      assert {:error, {:unparseable, %{field: "MEAN_MOTION", message: "is out of range"}}} =
               Omm.parse(%{@omm | "MEAN_MOTION" => huge})

      assert {:error, {:unparseable, %{field: "NORAD_CAT_ID"}}} =
               Omm.parse(%{@omm | "NORAD_CAT_ID" => huge})

      assert {:error, {:unparseable, %{field: "ELEMENT_SET_NO"}}} =
               Omm.parse(Map.put(@omm, "ELEMENT_SET_NO", "10000000000"))
    end
  end

  describe "validation" do
    test "accepts the ISS set and refuses non-physical elements" do
      assert {:ok, _} = ElementSets.parse({:tle, @tle}, @now)

      assert {:error, {:non_physical, %{field: "eccentricity"}}} =
               ElementSets.parse({:omm, %{@omm | "ECCENTRICITY" => 1.0}}, @now)

      assert {:error, {:non_physical, %{field: "mean_motion"}}} =
               ElementSets.parse({:omm, %{@omm | "MEAN_MOTION" => 0}}, @now)

      assert {:error, {:non_physical, %{field: "inclination"}}} =
               ElementSets.parse({:omm, %{@omm | "INCLINATION" => 181}}, @now)

      assert {:error, {:non_physical, %{field: "raan"}}} =
               ElementSets.parse({:omm, %{@omm | "RA_OF_ASC_NODE" => 361}}, @now)
    end

    test "refuses an epoch more than a day ahead of now" do
      assert {:ok, _} = ElementSets.parse({:tle, @tle}, ~U[2008-09-19 12:25:41Z])

      assert {:error, {:epoch_in_future, %{epoch: "2008-09-20T12:25:40.104192Z"}}} =
               ElementSets.parse({:tle, @tle}, ~U[2008-09-19 12:25:39Z])
    end

    test "holds the one-day limit to the microsecond" do
      assert {:ok, _} = ElementSets.parse({:tle, @tle}, ~U[2008-09-19 12:25:40.104192Z])

      assert {:error, {:epoch_in_future, _}} =
               ElementSets.parse({:tle, @tle}, ~U[2008-09-19 12:25:40.104191Z])
    end
  end

  defp checksum(line) do
    line
    |> String.to_charlist()
    |> Enum.reduce(0, fn
      char, sum when char in ?0..?9 -> sum + char - ?0
      ?-, sum -> sum + 1
      _char, sum -> sum
    end)
    |> rem(10)
  end
end
