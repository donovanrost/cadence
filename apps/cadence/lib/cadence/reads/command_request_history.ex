defmodule Cadence.Reads.CommandRequestHistory do
  @moduledoc """
  U68 R3/R4 (fe-ops, parity A3 + A4b/c): one command request's (a group member's) release
  attempts, newest first, and its verifiers, oldest first, each with the record that matched it.
  25 per page; `attempts_after` / `verifiers_after` take the last id of the page before.

  Contract: docs/apogee/api/commanding.md § Request history.
  """

  import Ecto.Query

  alias Cadence.Accounts.MemberNames
  alias Cadence.Auth

  alias Cadence.Commanding.{
    CommandReleaseAttemptRow,
    CommandRequestRow,
    CommandVerifierInstanceRow,
    ReleaseTargetGuard
  }

  alias Cadence.Reads.CommandRequestHistory.{Contacts, Evidence}
  alias Cadence.Repo

  @page 25

  @spec load(binary(), binary(), binary(), keyword()) ::
          {:ok, map()} | {:error, :command_request_not_found | :invalid_cursor}
  def load(org, mission, request_id, opts \\ []) do
    with {:ok, request} <- request(org, mission, request_id),
         {:ok, attempts, attempts_next} <- attempts(request, opts[:attempts_after]),
         {:ok, verifiers, verifiers_next} <- verifiers(request, opts[:verifiers_after]) do
      spacecraft_id = spacecraft_id(org, mission, request.source_endpoint_ref)

      contacts =
        Contacts.load(org, mission, Enum.map(attempts, & &1.realized_contact_id), spacecraft_id)

      evidence = Evidence.load(org, mission, request_id, verifiers)

      {:ok,
       %{
         request_id: request_id,
         spacecraft_id: spacecraft_id,
         attempts: Enum.map(attempts, &attempt(&1, contacts)),
         attempts_next: attempts_next,
         verifiers: Enum.map(verifiers, &verifier(&1, evidence)),
         verifiers_next: verifiers_next
       }}
    end
  end

  defp request(org, mission, id) do
    case Repo.one(
           from(r in CommandRequestRow,
             where:
               r.organization_id == ^org and r.mission_id == ^mission and
                 r.command_request_id == ^id
           )
         ) do
      nil -> {:error, :command_request_not_found}
      row -> {:ok, row}
    end
  end

  defp spacecraft_id(org, mission, ref) do
    case ReleaseTargetGuard.target(org, mission, ref) do
      {:ok, id} -> id
      _unknown -> nil
    end
  end

  defp scoped(schema, request),
    do:
      from(row in schema,
        where:
          row.organization_id == ^request.organization_id and
            row.mission_id == ^request.mission_id and
            row.command_request_id == ^request.command_request_id
      )

  # Newest first by (attempted_at, id).
  defp attempts(request, after_id) do
    base = scoped(CommandReleaseAttemptRow, request)

    with {:ok, query} <- after_attempt(base, after_id) do
      query
      |> order_by([a], desc: a.attempted_at, desc: a.command_release_attempt_id)
      |> limit(@page + 1)
      |> Repo.all()
      |> page(& &1.command_release_attempt_id)
    end
  end

  defp after_attempt(query, nil), do: {:ok, query}

  defp after_attempt(query, id) do
    case Repo.one(where(query, [a], a.command_release_attempt_id == ^id)) do
      nil ->
        {:error, :invalid_cursor}

      cursor ->
        {:ok,
         where(
           query,
           [a],
           fragment(
             "(?, ?) < (?, ?)",
             a.attempted_at,
             a.command_release_attempt_id,
             ^cursor.attempted_at,
             ^cursor.command_release_attempt_id
           )
         )}
    end
  end

  # Oldest first by (inserted_at, id), as they were created.
  defp verifiers(request, after_id) do
    base = scoped(CommandVerifierInstanceRow, request)

    with {:ok, query} <- after_verifier(base, after_id) do
      query
      |> order_by([v], asc: v.inserted_at, asc: v.command_verifier_instance_id)
      |> limit(@page + 1)
      |> Repo.all()
      |> page(& &1.command_verifier_instance_id)
    end
  end

  defp after_verifier(query, nil), do: {:ok, query}

  defp after_verifier(query, id) do
    case Repo.one(where(query, [v], v.command_verifier_instance_id == ^id)) do
      nil ->
        {:error, :invalid_cursor}

      cursor ->
        {:ok,
         where(
           query,
           [v],
           fragment(
             "(?, ?) > (?, ?)",
             v.inserted_at,
             v.command_verifier_instance_id,
             ^cursor.inserted_at,
             ^cursor.command_verifier_instance_id
           )
         )}
    end
  end

  defp page(rows, id_of) do
    shown = Enum.take(rows, @page)
    next = if length(rows) > @page, do: id_of.(List.last(shown))
    {:ok, shown, next}
  end

  defp attempt(row, contacts) do
    %{
      attempt_id: row.command_release_attempt_id,
      state: row.lifecycle_state,
      uncertain: row.lifecycle_state == "release_uncertain",
      failure_reason: row.failure_reason,
      failure:
        row.lifecycle_state
        |> failure(row.failure_reason)
        |> resolved_by(row.resolution_evidence, row.organization_id),
      contact: Contacts.contact(contacts, row.realized_contact_id, row.attempted_at),
      path_id: row.path_id,
      transport_binding_id: row.transport_binding_id,
      encoded_size_bytes: row.encoded_size_bytes,
      attempted_at: row.attempted_at,
      released_at: row.released_at
    }
  end

  # U68 R3 (fe-ops U70): `failure_reason` is an inspected term, so the wire also says what kind
  # of failure it is and a code. Refusal codes are the leading atom, the same vocabulary as a
  # named release's `stopped.reason.code` (GroupRelease.encode_reason).
  @doc false
  def failure(_state, nil), do: nil
  def failure(_state, "resolved: " <> outcome), do: %{kind: "resolved", code: outcome}
  def failure(_state, "refused: " <> term), do: %{kind: "refused", code: leading_atom(term)}
  def failure("release_uncertain", term), do: %{kind: "uncertain", code: leading_atom(term)}
  def failure(_state, term), do: %{kind: "refused", code: leading_atom(term)}

  # ux U29: a resolution names who and when, from the attempt's resolution log (the last entry
  # with that outcome). Other kinds carry `by: nil, at: nil`.
  @doc false
  def resolved_by(failure, evidence, org \\ nil)
  def resolved_by(nil, _evidence, _org), do: nil

  def resolved_by(%{kind: "resolved", code: outcome} = failure, evidence, org) do
    entry =
      (evidence || %{})
      |> Map.get("entries", [])
      |> Enum.filter(&(is_map(&1) and &1["outcome"] == outcome))
      |> List.last()

    Map.merge(failure, %{
      by: actor(entry && entry["actor"], org),
      at: time(entry && entry["recorded_at"])
    })
  end

  def resolved_by(failure, _evidence, _org), do: Map.merge(failure, %{by: nil, at: nil})

  # A resolution's actor is a person or a service identity (an API credential), never Cadence
  # itself: an automatic timeout records outcome `unknown`, which isn't a resolved failure.
  # #470 (#146 C1): a person only while an active member of the request's organization (with
  # their id, name nil without one), a service only from its live row there; anyone else has no
  # id and no name. Never a name or email stored in the log. The wire's kinds stay `user` and
  # `service_identity`; an entry without a kind has no id.
  defp actor(%{"kind" => "user", "id" => id}, org) when is_binary(id) and is_binary(org) do
    case Map.fetch(MemberNames.members(org, [id]), id) do
      {:ok, name} -> %{kind: "user", id: id, name: name}
      :error -> %{kind: "user", id: nil, name: nil}
    end
  end

  defp actor(%{"kind" => "service", "id" => id}, org) when is_binary(id) and is_binary(org) do
    case Map.fetch(Auth.organization_service_identities(org, [id]), id) do
      {:ok, name} -> %{kind: "service_identity", id: id, name: name}
      :error -> %{kind: "service_identity", id: nil, name: nil}
    end
  end

  defp actor(%{"kind" => "user"}, _org), do: %{kind: "user", id: nil, name: nil}
  defp actor(%{"kind" => "service"}, _org), do: %{kind: "service_identity", id: nil, name: nil}
  defp actor(%{}, _org), do: %{kind: nil, id: nil, name: nil}
  defp actor(_none, _org), do: nil

  defp time(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _offset} -> at
      _invalid -> nil
    end
  end

  defp time(_none), do: nil

  defp leading_atom(term) do
    case Regex.run(~r/^\{?:"?([A-Za-z_][A-Za-z0-9_]*)/, term) do
      [_match, atom] -> atom
      nil -> nil
    end
  end

  defp verifier(row, evidence) do
    {status, record} = Evidence.for_verifier(evidence, row)

    %{
      instance_id: row.command_verifier_instance_id,
      attempt_id: row.command_release_attempt_id,
      verifier_id: row.verifier_id,
      name: row.verifier_name,
      phase: row.phase,
      severity: row.severity,
      state: row.lifecycle_state,
      failure_code: row.failure_reason,
      matched_at: row.matched_at,
      timeout_at: row.timeout_at,
      evidence_status: status,
      evidence: record
    }
  end
end
