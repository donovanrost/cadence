defmodule Cadence.CCSDS.PDUHandler do
  @moduledoc """
  Behavior for application-level handlers that consume decoded PDUs and emit
  domain events.
  """

  alias Cadence.CCSDS.Core.PDU

  @callback init(keyword()) :: {:ok, term()}

  @callback accepts?(PDU.t(), map()) :: boolean()

  @callback handle_pdu(PDU.t(), map(), term()) ::
              {:ok, [Cadence.Events.event()], term()}
              | {:skip, reason :: term(), term()}
              | {:error, reason :: term(), term()}
end
