defmodule Cadence.Protocol.ScidRoutes do
  @moduledoc """
  What a source endpoint's partition may accept by frame SCID (#1078 P5 slice E1b). Pure: the data
  comes from `Cadence.Control.ScidRoutes.build/3`, once per partition plan and refreshed on a clock
  for a relay, never per packet or per frame.

    * the endpoint's **own** craft SCID: its frames are `:direct`;
    * for a **relay** endpoint (`relay.origin_spacecraft_ids`, ground's #1146) each declared origin
      craft's SCID: its frames are `{:relayed, craft}`, resolved only inside that set (DECISIONS
      #115: SCID routing never happens mission-wide). An origin craft that was archived is
      skipped, not an error: its frames are `{:archived, craft}`;
    * any other SCID is a `:mismatch`.

  An endpoint whose craft has no SCID can't be checked, so nothing is refused on it (that is what
  runs today: the check existed only for contact paths that named the craft's SCID).
  """

  defstruct source_endpoint_id: nil,
            own_spacecraft_id: nil,
            own_scid: nil,
            routes: %{}

  @type route :: %{spacecraft_id: binary(), state: :active | :archived}
  @type t :: %__MODULE__{
          source_endpoint_id: binary() | nil,
          own_spacecraft_id: binary() | nil,
          own_scid: non_neg_integer() | nil,
          routes: %{non_neg_integer() => route()}
        }
  @type verdict :: :direct | {:relayed, binary()} | {:archived, binary()} | :mismatch

  @doc "Routes that check nothing (an endpoint with no craft or no SCID, or one that can't be read)."
  @spec none() :: t()
  def none, do: %__MODULE__{}

  @doc """
  The routes of an endpoint: its craft and that craft's SCID (`nil` when it has none), and the
  `{spacecraft_id, scid, :active | :archived}` of each declared origin craft (those without a SCID
  can't be routed to and are left out).
  """
  @spec new(binary(), binary() | nil, non_neg_integer() | nil, [
          {binary(), non_neg_integer() | nil, :active | :archived}
        ]) :: t()
  def new(source_endpoint_id, own_spacecraft_id, own_scid, origins) do
    own_scid = if is_integer(own_scid), do: own_scid

    routes =
      for {id, scid, state} <- origins,
          is_integer(scid),
          id != own_spacecraft_id,
          scid != own_scid,
          into: %{},
          do: {scid, %{spacecraft_id: id, state: state}}

    %__MODULE__{
      source_endpoint_id: source_endpoint_id,
      own_spacecraft_id: own_spacecraft_id,
      own_scid: own_scid,
      routes: routes
    }
  end

  @doc "Whether the endpoint declares a relay set with a routable origin."
  @spec relay?(t()) :: boolean()
  def relay?(%__MODULE__{routes: routes}), do: map_size(routes) > 0

  @doc "Whether any frame can be refused on this endpoint."
  @spec checks?(t()) :: boolean()
  def checks?(%__MODULE__{own_scid: scid} = routes), do: is_integer(scid) or relay?(routes)

  @doc "What a frame with this SCID is on this endpoint."
  @spec classify(t(), non_neg_integer()) :: verdict()
  def classify(%__MODULE__{own_scid: scid}, scid) when is_integer(scid), do: :direct

  def classify(%__MODULE__{routes: routes} = index, scid) do
    case Map.fetch(routes, scid) do
      {:ok, %{spacecraft_id: id, state: :active}} -> {:relayed, id}
      {:ok, %{spacecraft_id: id, state: :archived}} -> {:archived, id}
      :error -> if checks?(index), do: :mismatch, else: :direct
    end
  end
end
