defmodule Cadence.Reads.ContactStart do
  @moduledoc """
  Who started a realized contact and when it went live, for the console's contact rows: Uplink's
  named-release block (api U46) and the hand-started rows on the passes read (U78).
  """

  alias Cadence.Accounts.MemberNames
  alias Cadence.Contacts.RealizedContact

  @doc """
  Who started it (domain's metadata "started_by" {kind, id}); nil before it starts. kind is
  user | service | system; only a user is named, from `people/2` (#146, #468): an active member
  of the mission's organization keeps their id and name (nil when they have none); any other
  person reads id and name nil, never an email.
  """
  @spec started_by(RealizedContact.t(), %{binary() => binary() | nil}) :: map() | nil
  def started_by(
        %RealizedContact{metadata: %{"started_by" => %{"id" => id} = by}},
        people
      )
      when is_binary(id) do
    case by["kind"] do
      "user" -> person(id, people)
      "service" -> %{kind: "service", id: id, name: nil}
      _system -> %{kind: "system", id: id, name: nil}
    end
  end

  def started_by(_contact, _people), do: nil

  @doc "The people who started `contacts`, as `started_by/2` reads them: one lookup per read."
  @spec people(binary(), [RealizedContact.t()]) :: %{binary() => binary() | nil}
  def people(organization_id, contacts) do
    ids =
      for %RealizedContact{metadata: %{"started_by" => %{"kind" => "user", "id" => id}}} <-
            contacts,
          is_binary(id),
          uniq: true,
          do: id

    MemberNames.members(organization_id, ids)
  end

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

  defp person(id, people) do
    case Map.fetch(people, id) do
      {:ok, name} -> %{kind: "user", id: id, name: name}
      :error -> %{kind: "user", id: nil, name: nil}
    end
  end
end
