defmodule Cadence.Reads.PassIncompleteAtEnd do
  @moduledoc """
  A pass detail's `incomplete_at_end` (ux U67; domain's partial-frame consumer): bytes at the end
  of the pass that didn't form a complete frame or packet, so they weren't stored. From the
  settlement domain records on the realized contact,
  `metadata["settlement"]["incomplete_at_end"]` (one entry per path, only those with something
  given up), summed: `%{frame_bytes, packet_bytes}` (`packet_octets` on the record), or nil when
  nothing was cut off, the contact hasn't settled, or the record predates it.
  """

  alias Cadence.Contacts

  @spec read(binary(), binary(), binary() | nil) :: map() | nil
  def read(_org, _mission, nil), do: nil

  def read(org, mission, realized_contact_id) do
    case Contacts.fetch_realized_contact(org, mission, realized_contact_id) do
      {:ok, contact} -> from_metadata(contact.metadata)
      _missing -> nil
    end
  end

  @doc "The summed counts from a realized contact's metadata, or nil."
  @spec from_metadata(term()) :: map() | nil
  def from_metadata(%{} = metadata) do
    entries =
      case get_in(metadata, ["settlement", "incomplete_at_end"]) do
        list when is_list(list) -> list
        _none -> []
      end

    totals = %{
      frame_bytes: sum(entries, "frame_bytes"),
      packet_bytes: sum(entries, "packet_octets")
    }

    if totals.frame_bytes > 0 or totals.packet_bytes > 0, do: totals
  end

  def from_metadata(_metadata), do: nil

  defp sum(entries, key) do
    Enum.reduce(entries, 0, fn
      %{^key => n}, acc when is_integer(n) and n > 0 -> acc + n
      _entry, acc -> acc
    end)
  end
end
