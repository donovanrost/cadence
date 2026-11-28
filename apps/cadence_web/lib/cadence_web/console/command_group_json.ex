defmodule CadenceWeb.Console.CommandGroupJSON do
  @moduledoc """
  Wire shapes for console command groups, preflight and policies. Contract:
  docs/apogee/api/commanding.md. Atoms become strings; argument values go out
  as `*_json` strings so 64-bit integers survive JavaScript.
  """

  alias Cadence.Control.Commanding.GroupDecision
  alias Cadence.Reads.CommandGroups.Page

  @doc "M26 verifier series (atoms to strings; values already JSON text)."
  @spec verifier_series(map()) :: map()
  def verifier_series(series), do: encode(series)

  @spec preflight(map()) :: map()
  def preflight(preflight) do
    %{
      valid: preflight.valid?,
      digest: preflight.digest,
      members: preflight.members,
      second_go_required: preflight.policy && preflight.policy.second_go_required,
      targets:
        Enum.map(
          preflight.targets,
          &Map.take(&1, [
            :index,
            :spacecraft_id,
            :source_endpoint_id,
            :name,
            :scid,
            :failure,
            :catalog_revision
          ])
        ),
      # U51: per stacked command, the groups of targets that share a verifier set.
      commands: Map.get(preflight, :commands, []),
      checks: Enum.map(preflight.checks, &check/1)
    }
    |> encode()
  end

  @spec summary(map()) :: map()
  def summary(group), do: encode(group)

  @doc """
  The group read: the summary, its commands, every target and event, and (#795) `targets_page`
  (`{total, revision, next_cursor}`) and `events_page` (`{total, next_cursor}`) saying how many
  there are. `show_first_page/1` is the same read with only the first pages; the console moves
  onto it with its paging.
  """
  @spec show(map()) :: map()
  def show(view), do: view |> Page.totals() |> render()

  @doc "`show/1` with the first targets and the latest events, and a cursor to page the rest."
  @spec show_first_page(map()) :: map()
  def show_first_page(view), do: view |> Page.first() |> render()

  @doc """
  The `group` push for a paged client (#795): `show_first_page/1` without the targets and events,
  which the client refetches when `targets_page.revision` or `events_page.total` changes.
  """
  @spec push(map()) :: map()
  def push(view), do: view |> Page.first() |> Map.drop([:targets, :events]) |> render()

  @spec targets([map()]) :: [map()]
  def targets(targets), do: encode(targets)

  @spec events([map()]) :: [map()]
  def events(events), do: encode(events)

  defp render(view) do
    group = view.group

    groups = Map.get(view, :verifier_groups, %{})
    resolved = Map.get(view, :resolved_arguments, %{})

    view
    |> Map.drop([:group, :verifier_groups, :resolved_arguments])
    |> Map.merge(%{
      review_token: GroupDecision.review_token(group),
      log_entry: group.log_entry,
      sent_back_from: group.sent_back_from,
      target_query: group.target_query,
      commands:
        Enum.map(
          group.commands,
          &(command(&1)
            |> Map.put("verifier_groups", Map.get(groups, &1["position"], []))
            |> Map.put("resolved_arguments", Map.get(resolved, &1["position"], [])))
        ),
      release: group.release,
      policy: group.policy,
      decided_by: group.decided_by,
      decided_at: group.decided_at,
      decision: group.decision,
      aborted_by: group.aborted_by,
      aborted_at: group.aborted_at,
      abort_reason: group.abort_reason,
      abort_result: group.abort_result,
      resolved_at: group.resolved_at
    })
    |> encode()
  end

  @spec endpoints([map()]) :: map()
  def endpoints(endpoints), do: encode(%{spacecraft: endpoints})

  @spec policies([map()]) :: map()
  def policies(policies), do: encode(%{policies: policies})

  defp check(check), do: Map.update!(check, :result, &Atom.to_string/1)

  defp command(command) do
    {values, rest} = Map.pop(command, "argument_values", %{})
    {per_target, rest} = Map.pop(rest, "per_target", %{})

    rest
    |> Map.put("argument_values_json", Jason.encode!(values))
    |> Map.put(
      "per_target",
      Enum.map(per_target || %{}, fn {sc, target_values} ->
        %{"spacecraft_id" => sc, "argument_values_json" => Jason.encode!(target_values)}
      end)
    )
  end

  # JSON-safe encoding: atoms to strings (keeping nil/booleans), structs other than DateTime
  # dropped to maps, tuples to lists.
  defp encode(%DateTime{} = at), do: at
  defp encode(%_{} = struct), do: struct |> Map.from_struct() |> encode()
  defp encode(map) when is_map(map), do: Map.new(map, fn {key, value} -> {key, encode(value)} end)
  defp encode(list) when is_list(list), do: Enum.map(list, &encode/1)
  defp encode(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> encode()

  defp encode(atom) when is_atom(atom) and atom not in [nil, true, false],
    do: Atom.to_string(atom)

  defp encode(value), do: value
end
