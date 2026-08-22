defmodule Cadence.CCSDS.CFDP.TLV do
  @moduledoc """
  Standard CFDP type-length-value parameters.
  """

  alias Cadence.CCSDS.CFDP.TLV

  @type t ::
          TLV.FilestoreRequest.t()
          | TLV.FilestoreResponse.t()
          | TLV.MessageToUser.t()
          | TLV.FaultHandlerOverride.t()
          | TLV.FlowLabel.t()
          | TLV.EntityID.t()
end
