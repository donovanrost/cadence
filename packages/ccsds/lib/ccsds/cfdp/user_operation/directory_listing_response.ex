defmodule CCSDS.CFDP.UserOperation.DirectoryListingResponse do
  @moduledoc "Typed Directory Listing Response reserved message."

  @type t :: %__MODULE__{
          listing_response: :successful | :unsuccessful,
          directory_name: binary(),
          directory_file_name: binary()
        }

  defstruct listing_response: :successful, directory_name: <<>>, directory_file_name: <<>>
end
