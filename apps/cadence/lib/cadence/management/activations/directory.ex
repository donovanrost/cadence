defmodule Cadence.Management.Activations.Directory do
  @moduledoc """
  Console reads of a mission's activation requests (L10, docs/apogee/api/activations.md): one
  page of a tab (`:pending` waiting for approval, `:decided` approved, rejected, withdrawn or
  superseded), newest first
  on a `{requested_at, id}` cursor, a mission-checked fetch, and each request's latest human
  decision.
  """

  import Ecto.Query

  alias Cadence.Management.Activations.{
    ActivationDecisionRow,
    ActivationRequest,
    ActivationRequestRow
  }

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @page 25

  @spec page(binary(), binary(), :pending | :decided, {DateTime.t(), binary()} | nil) ::
          {[ActivationRequest.t()], boolean()}
  def page(organization_id, mission_id, tab, before) do
    rows =
      ActivationRequestRow
      |> where([r], r.organization_id == ^organization_id and r.mission_id == ^mission_id)
      |> tab(tab)
      |> before(before)
      |> order_by([r], desc: r.requested_at, desc: r.activation_request_id)
      |> limit(@page + 1)
      |> Repo.all()

    {rows |> Enum.take(@page) |> Enum.map(&ActivationRequestRow.to_domain/1),
     length(rows) > @page}
  end

  @doc "A request of this mission (Management.Activations.fetch/2 checks only the organization)."
  @spec fetch(binary(), binary(), binary()) ::
          {:ok, ActivationRequest.t()} | {:error, :activation_request_not_found}
  def fetch(organization_id, mission_id, request_id) do
    case Repo.get_by(ActivationRequestRow,
           activation_request_id: request_id,
           organization_id: organization_id,
           mission_id: mission_id
         ) do
      nil -> {:error, :activation_request_not_found}
      row -> {:ok, ActivationRequestRow.to_domain(row)}
    end
  end

  @doc "Each request's latest decision: `%{request_id => %{decision, actor, reason, decided_at}}`."
  @spec decisions(binary(), binary(), [binary()]) :: %{binary() => map()}
  def decisions(_organization_id, _mission_id, []), do: %{}

  def decisions(organization_id, mission_id, request_ids) do
    ActivationDecisionRow
    |> where(
      [d],
      d.organization_id == ^organization_id and d.mission_id == ^mission_id and
        d.activation_request_id in ^request_ids
    )
    |> order_by([d], asc: d.decided_at)
    |> Repo.all()
    |> Map.new(fn d ->
      {d.activation_request_id,
       %{
         decision: d.decision,
         actor: JsonDocument.unwrap_value(d.actor_document) || %{},
         actor_id: d.actor_id,
         reason: d.reason,
         decided_at: d.decided_at
       }}
    end)
  end

  defp tab(query, :pending), do: where(query, [r], r.state == :approval_pending)

  defp tab(query, :decided),
    do: where(query, [r], r.state in [:approved, :rejected, :withdrawn, :superseded])

  defp before(query, nil), do: query

  defp before(query, {%DateTime{} = at, id}),
    do:
      where(
        query,
        [r],
        r.requested_at < ^at or (r.requested_at == ^at and r.activation_request_id < ^id)
      )
end
