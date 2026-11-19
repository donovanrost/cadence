defmodule Cadence.Reads.ContactStart do
  @moduledoc """
  Who started a realized contact and when it went live, for the console's contact rows: Uplink's
  named-release block (api U46) and the hand-started rows on the passes read (U78).
  """

  alias Cadence.Accounts
  alias Cadence.Contacts.RealizedContact

  @doc """
  Who started it (domain's metadata "started_by" {kind, id}); nil before it starts. kind is
  user | service | system; only a user is named.
  """
  @spec started_by(RealizedContact.t()) :: map() | nil
  def started_by(%RealizedContact{metadata: %{"started_by" => %{"id" => id} = by}})
      when is_binary(id) do
    case by["kind"] do
      "user" -> %{kind: "user", id: id, name: user_name(id)}
      "service" -> %{kind: "service", id: id, name: nil}
      _system -> %{kind: "system", id: id, name: nil}
    end
  end

  def started_by(_contact), do: nil

  @doc "When it went live: the start after a failed one (U45), else when it was realized."
  @spec went_live_at(RealizedContact.t()) :: DateTime.t() | nil
  def went_live_at(%RealizedContact{} = contact) do
    case contact.metadata["start_failure"] do
      %{"started_at" => at} when is_binary(at) -> parse(at) || contact.realized_at
      _never_failed -> contact.realized_at
    end
  end

  @doc "When it closed: stopped, completed, or closed as never started (nil while open)."
  @spec ended_at(RealizedContact.t()) :: DateTime.t() | nil
  def ended_at(%RealizedContact{metadata: metadata} = contact) do
    at =
      metadata["stopped_at"] || metadata["completed_at"] ||
        get_in(metadata, ["not_started", "at"])

    cond do
      is_binary(at) -> parse(at)
      contact.lifecycle_state in [:stopped, :completed] -> contact.realized_at
      true -> nil
    end
  end

  defp parse(at) do
    case DateTime.from_iso8601(at) do
      {:ok, parsed, _offset} -> parsed
      _invalid -> nil
    end
  end

  defp user_name(id) do
    case Accounts.fetch_user(id) do
      {:ok, user} -> user.display_name || user.email
      _missing -> nil
    end
  end
end
