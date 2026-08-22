defmodule CCSDS.CFDP.UserOperation.DirectoryListingRequest do
  @moduledoc "Typed Directory Listing Request reserved message."

  @type t :: %__MODULE__{directory_name: binary(), directory_file_name: binary()}
  defstruct directory_name: <<>>, directory_file_name: <<>>
end
