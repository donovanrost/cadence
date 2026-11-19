defmodule Cadence.IngressJournal.MetadataRecoveryTest do
  @moduledoc """
  Recovery never truncates an INTACT record because its metadata won't decode (domain's finding,
  11-14): `binary_to_term(:safe)` refuses an atom the VM hasn't created yet (its module not loaded,
  as on a lazily loading node right after boot), which is not a torn write. The journal loads the
  app's modules and retries once; if the metadata still won't decode, it refuses to open and keeps
  every byte.
  """
  use ExUnit.Case, async: false

  alias Cadence.IngressJournal.FileSystem

  # An atom name the VM never creates (it appears only inside this string).
  @unknown "journal_probe_xnone_key"

  @tag :tmp_dir
  test "a record whose metadata names an atom the VM doesn't have stops recovery without truncating",
       %{tmp_dir: tmp_dir} do
    opts = opts(tmp_dir)

    start_supervised!({FileSystem, opts}, id: :first)
    {:ok, _first} = FileSystem.append(opts[:name], <<1, 2, 3>>, DateTime.utc_now(), %{})
    {:ok, _second} = FileSystem.append(opts[:name], <<4, 5, 6>>, DateTime.utc_now(), %{})
    stop_supervised!(:first)

    [segment] = Path.wildcard(Path.join([tmp_dir, "*", "segment-*.cij"]))
    {first_record, second_record} = split_first_record(File.read!(segment))

    # The second record keeps its payload (and so its checksum) but its metadata now names an
    # atom the VM doesn't have: %{journal_probe_xnone_key => 1}, uncompressed external format.
    patched = first_record <> with_metadata(second_record, unknown_atom_metadata())
    File.write!(segment, patched)

    assert {:error, {{:ingress_journal_metadata_undecodable, ^segment, offset}, _child}} =
             start_supervised({FileSystem, opts}, id: :second)

    assert offset == byte_size(first_record)
    # Nothing was truncated: both records are still on disk.
    assert File.read!(segment) == patched
  end

  @tag :tmp_dir
  test "a genuinely torn tail is still truncated", %{tmp_dir: tmp_dir} do
    opts = opts(tmp_dir)

    start_supervised!({FileSystem, opts}, id: :first)
    {:ok, entry} = FileSystem.append(opts[:name], <<1, 2, 3>>, DateTime.utc_now(), %{})
    stop_supervised!(:first)

    [segment] = Path.wildcard(Path.join([tmp_dir, "*", "segment-*.cij"]))
    intact_size = File.stat!(segment).size
    File.write!(segment, <<0, 1, 2>>, [:append])

    start_supervised!({FileSystem, opts}, id: :second)
    assert {:ok, %{next_offset: next_offset}} = FileSystem.snapshot(opts[:name])
    assert next_offset == entry.end_offset
    assert File.stat!(segment).size == intact_size
  end

  defp opts(tmp_dir) do
    provider_binding_id = "provider-metadata-#{System.unique_integer([:positive])}"

    [
      name:
        {:via, Registry,
         {Cadence.Runtime.Registry, {:journal_metadata_test, provider_binding_id}}},
      mission_id: "mission-metadata",
      realized_contact_id: "contact-metadata",
      path_id: "path-metadata",
      provider_binding_id: provider_binding_id,
      base_path: tmp_dir,
      durability: :sync,
      max_bytes: 64 * 1_024,
      segment_bytes: 32 * 1_024,
      checkpoint_interval_ms: 60_000
    ]
  end

  # "CIJR", version 16, sequence 64, start offset 64, receipt 64, payload length 32, metadata
  # length 32, payload checksum 32 bytes: 70 bytes, then metadata, then payload.
  defp split_first_record(
         <<"CIJR", _::binary-size(26), payload_length::32, metadata_length::32,
           _::binary-size(32), _::binary>> = segment
       ) do
    first_size = 70 + metadata_length + payload_length
    <<first::binary-size(first_size), rest::binary>> = segment
    {first, rest}
  end

  defp with_metadata(
         <<prefix::binary-size(30), payload_length::32, metadata_length::32,
           checksum::binary-size(32), _metadata::binary-size(metadata_length),
           payload::binary-size(payload_length)>>,
         metadata
       ) do
    <<prefix::binary, payload_length::32, byte_size(metadata)::32, checksum::binary,
      metadata::binary, payload::binary>>
  end

  defp unknown_atom_metadata,
    do: <<131, 116, 1::32, 119, byte_size(@unknown), @unknown::binary, 97, 1>>
end
