defmodule CCSDS.CFDP.UserOperation do
  @moduledoc """
  Typed CCSDS Reserved CFDP Messages carried by Message-to-User TLVs.

  The library encodes and decodes standard proxy and directory messages. Acting
  on those messages, authorizing them, and issuing subsidiary transactions are
  caller concerns.
  """

  alias CCSDS.CFDP.UserOperation

  @type t ::
          UserOperation.OriginatingTransactionID.t()
          | UserOperation.ProxyPutRequest.t()
          | UserOperation.ProxyMessageToUser.t()
          | UserOperation.ProxyFilestoreRequest.t()
          | UserOperation.ProxyFaultHandlerOverride.t()
          | UserOperation.ProxyTransmissionMode.t()
          | UserOperation.ProxyFlowLabel.t()
          | UserOperation.ProxySegmentationControl.t()
          | UserOperation.ProxyClosureRequest.t()
          | UserOperation.ProxyPutResponse.t()
          | UserOperation.ProxyFilestoreResponse.t()
          | UserOperation.ProxyPutCancel.t()
          | UserOperation.DirectoryListingRequest.t()
          | UserOperation.DirectoryListingResponse.t()
end
