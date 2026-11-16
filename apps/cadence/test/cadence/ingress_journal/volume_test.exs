defmodule Cadence.IngressJournal.VolumeTest do
  @moduledoc "The ingress journal's disk: its usage (fail-safe :unknown) and its streams (ux U66)."
  use ExUnit.Case, async: true

  alias Cadence.IngressJournal.{FileSystem, Volume}

  describe "usage/2" do
    test "reads size and used bytes from the disk holding the path" do
      reader = fn "/journal" -> [{~c"/data", 1_000, 250, 75}] end

      assert {:ok, %{size_bytes: 1_024_000, used_bytes: 768_000, percent: 75.0}} =
               Volume.usage("/journal", reader: reader)
    end

    test "is :unknown when the disk can't be read (disksup off, no such path, a crash)" do
      assert :unknown = Volume.usage("/journal", reader: fn _ -> [] end)
      assert :unknown = Volume.usage("/journal", reader: fn p -> [{p, 0, 0, 0}] end)
      assert :unknown = Volume.usage("/journal", reader: fn _ -> raise "boom" end)
      assert :unknown = Volume.usage("/journal", reader: fn _ -> exit(:noproc) end)
    end

    test "without disksup running (the test env) the real reader is :unknown" do
      assert Process.whereis(:disksup) == nil
      assert :unknown = Volume.usage(System.tmp_dir!())
    end
  end

  describe "streams/1" do
    @tag :tmp_dir
    test "lists every stored stream with its bytes, largest first", %{tmp_dir: base_path} do
      small = journal!(base_path, "contact-small", "path-a", 1)
      large = journal!(base_path, "contact-large", "path-a", 20)

      assert [
               %{mission_id: "mission-volume", realized_contact_id: "contact-large", bytes: big},
               %{realized_contact_id: "contact-small", bytes: little}
             ] = Volume.streams(base_path)

      assert big > little and little > 0
      for journal <- [small, large], do: GenServer.stop(journal)
    end

    @tag :tmp_dir
    test "an empty base path has none", %{tmp_dir: base_path} do
      assert Volume.streams(base_path) == []
    end
  end

  defp journal!(base_path, contact, path_id, records) do
    {:ok, journal} =
      FileSystem.start_link(
        mission_id: "mission-volume",
        realized_contact_id: contact,
        path_id: path_id,
        provider_binding_id: "binding-" <> contact,
        base_path: base_path,
        durability: :sync
      )

    for _ <- 1..records,
        do: {:ok, _} = FileSystem.append(journal, :binary.copy("x", 1_000), DateTime.utc_now())

    journal
  end
end
