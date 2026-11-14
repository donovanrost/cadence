defmodule Cadence.Reads.OrganizationAudit.CommandLines do
  @moduledoc """
  The audit's commanding sentences (ux U59). A group is named by its label, "SET_MODE and 2
  more for 12 spacecraft"; Cadence's own cancels say why in words, never the raw reason.
  """

  @check_labels %{
    "identity" => "Identity",
    "catalog" => "Catalog",
    "size" => "Size",
    "conflicts" => "Conflicts",
    "contact" => "Contact",
    "two_person" => "Two-person",
    "changed_since_submit" => "Since submit"
  }

  @doc "The group's label, or \"a command group\" when it's gone."
  @spec label(map() | nil) :: String.t()
  def label(nil), do: "a command group"

  def label(%{commands: commands, target_count: targets}) do
    named =
      case commands do
        [] -> "commands"
        [one] -> one
        [first | rest] -> "#{first} and #{length(rest)} more"
      end

    "#{named} for #{count(targets, "spacecraft", "spacecraft")}"
  end

  @doc "submitted: who submitted it, or resent with the original's send-back time and title."
  @spec submitted(map(), map() | nil, map()) :: String.t()
  def submitted(event, group, resent) do
    base =
      case resent do
        %{at: at, title: title} ->
          "Resent #{label(group)} (sent back at #{hhmm(at)}#{quoted(title)})"

        _none ->
          "Submitted #{label(group)}"
      end

    base <> second_go(event.payload) <> own_values(group)
  end

  @spec decision(atom() | String.t(), map(), map() | nil) :: String.t()
  def decision(kind, payload, group) do
    case to_string(kind) do
      "approved" -> "Gave GO on #{label(group)}"
      "approved_with_exclusions" -> "Gave GO on #{label(group)}, excluding #{excluded(payload)}"
      "rejected" -> "Gave NO-GO on #{label(group)}"
      "sent_back" -> "Sent back #{label(group)}"
    end
  end

  @spec aborted(map(), map() | nil) :: String.t()
  def aborted(payload, group) do
    canceled = payload["canceled"] || 0
    started = length(payload["already_started"] || [])

    "Aborted #{label(group)}: #{count(canceled, "uplink", "uplinks")} canceled, " <>
      "#{started} already sent"
  end

  @doc "U46 named release; `contact` is `%{code, at}` or nil."
  @spec released(map(), map() | nil, map() | nil) :: String.t()
  def released(payload, group, contact) do
    released = count(length(payload["released_entry_ids"] || []), "uplink", "uplinks")
    where = contact_words(contact)

    into =
      if payload["booked"] == false,
        do: "into a contact that wasn't a booked pass#{if where, do: " (#{where})", else: ""}",
        else: if(where, do: "into the #{where} pass", else: "into its contact")

    "Released #{released} of #{label(group)} #{into}" <> stopped(payload)
  end

  @spec hold_acknowledged(map(), map() | nil) :: String.t()
  def hold_acknowledged(payload, group) do
    check = Map.get(@check_labels, payload["key"], words(payload["key"]))
    "Acknowledged the #{check} HOLD on #{label(group)}"
  end

  @doc "An operator canceled one member of a group."
  @spec member_canceled(String.t(), String.t() | nil, map() | nil) :: String.t()
  def member_canceled(command, spacecraft, group),
    do: "Canceled #{command}#{on(spacecraft)} from #{label(group)}"

  @doc "Cadence's own cancels of a group's members, folded per reason (director 11-15)."
  @spec group_canceled(non_neg_integer(), String.t() | nil, [String.t()], map() | nil) ::
          String.t()
  def group_canceled(n, reason, archived, group) do
    base = "Canceled #{count(n, "uplink", "uplinks")} of #{label(group)}"

    case reason_key(reason) do
      "expired" -> base <> ": they expired before release"
      "release_basis_changed" -> base <> ": what they were approved against changed"
      "catalog_changed" -> base <> ": the catalog changed"
      "spacecraft_archived" -> base <> ": " <> archived_words(archived)
      "commanding_disabled" -> base <> ": commanding was turned off for " <> named(archived)
      _unknown -> base <> "."
    end
  end

  @doc "One standalone request canceled: by an operator (reason beside it) or by Cadence."
  @spec request_canceled(String.t(), String.t() | nil, boolean(), String.t() | nil) ::
          String.t()
  def request_canceled(command, _spacecraft, false, _reason), do: "Canceled #{command}"

  def request_canceled(command, spacecraft, true, reason) do
    base = "Canceled #{command}#{on(spacecraft)}"

    case reason_key(reason) do
      "expired" -> base <> ": it expired before release"
      "release_basis_changed" -> base <> ": what it was approved against changed"
      "catalog_changed" -> base <> ": the catalog changed"
      "spacecraft_archived" -> base <> ": the spacecraft was archived"
      "commanding_disabled" -> base <> ": commanding was turned off for it"
      _unknown -> base <> "."
    end
  end

  # "catalog_changed: <change set>" and similar carry an id after the key.
  defp reason_key(nil), do: nil
  defp reason_key(reason), do: reason |> String.split(":", parts: 2) |> hd() |> String.trim()

  defp archived_words([one]), do: "#{one} was archived"
  defp archived_words(names), do: "#{length(names)} of its spacecraft were archived"

  defp named([one]), do: one
  defp named(names), do: "#{length(names)} of its spacecraft"

  defp second_go(%{"second_go_required" => true}), do: " · needs a second GO"
  defp second_go(_payload), do: ""

  defp own_values(%{own_values: 1}), do: " · 1 spacecraft has its own values"

  defp own_values(%{own_values: n}) when is_integer(n) and n > 1,
    do: " · #{n} spacecraft have their own values"

  defp own_values(_group), do: ""

  defp excluded(payload), do: count(length(payload["excluded"] || []), "spacecraft", "spacecraft")

  defp stopped(%{"stopped" => %{} = _stopped} = payload) do
    left = length(payload["not_attempted_entry_ids"] || [])
    " · then stopped, #{count(left, "uplink", "uplinks")} still queued"
  end

  defp stopped(_payload), do: ""

  defp contact_words(%{code: code, at: %DateTime{} = at}) when is_binary(code),
    do: "#{code} #{hhmm(at)}"

  defp contact_words(%{at: %DateTime{} = at}), do: hhmm(at)
  defp contact_words(_none), do: nil

  defp on(nil), do: ""
  defp on(spacecraft), do: " on #{spacecraft}"

  defp quoted(title) when is_binary(title) and title != "", do: ": “#{title}”"
  defp quoted(_title), do: ""

  defp hhmm(%DateTime{} = at), do: Calendar.strftime(at, "%H:%MZ")

  defp count(1, one, _many), do: "1 #{one}"
  defp count(n, _one, many), do: "#{n} #{many}"

  defp words(nil), do: "preflight"
  defp words(key), do: key |> String.replace("_", " ") |> String.capitalize()
end
