defmodule Cadence.CCSDS.CFDP.TLV.FilestoreRequest do
  @moduledoc """
  CFDP Filestore Request TLV.
  """

  @type action ::
          :create_file
          | :delete_file
          | :rename_file
          | :append_file
          | :replace_file
          | :create_directory
          | :remove_directory
          | :deny_file
          | :deny_directory

  @type t :: %__MODULE__{
          action: action(),
          first_file_name: binary(),
          second_file_name: binary() | nil
        }

  defstruct action: nil,
            first_file_name: <<>>,
            second_file_name: nil

  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_map(attrs) or is_list(attrs), do: struct(__MODULE__, Map.new(attrs))
end
