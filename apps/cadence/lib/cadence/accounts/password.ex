defmodule Cadence.Accounts.Password do
  @moduledoc false

  import Bitwise

  @pbkdf2_iterations Application.compile_env(:cadence, :password_hash_iterations, 100_000)
  @pbkdf2_length 32

  @spec hash_password(binary()) :: %{
          password_hash: binary(),
          password_salt: binary(),
          password_iterations: pos_integer()
        }
  def hash_password(password) when is_binary(password) do
    salt = :crypto.strong_rand_bytes(16)
    iterations = @pbkdf2_iterations

    %{
      password_hash: derive_key(password, salt, iterations),
      password_salt: Base.encode64(salt),
      password_iterations: iterations
    }
  end

  @spec verify_password(binary(), binary(), binary(), pos_integer()) :: boolean()
  def verify_password(password, password_hash, password_salt, password_iterations)
      when is_binary(password) and is_binary(password_hash) and is_binary(password_salt) and
             is_integer(password_iterations) and password_iterations > 0 do
    with {:ok, salt} <- Base.decode64(password_salt),
         {:ok, expected_hash} <- Base.decode64(password_hash) do
      actual_hash =
        :crypto.pbkdf2_hmac(:sha256, password, salt, password_iterations, @pbkdf2_length)

      secure_compare(actual_hash, expected_hash)
    else
      :error -> false
    end
  end

  defp derive_key(password, salt, iterations) do
    :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, @pbkdf2_length)
    |> Base.encode64()
  end

  defp secure_compare(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {lhs, rhs}, acc ->
      bor(acc, bxor(lhs, rhs))
    end)
    |> Kernel.==(0)
  end

  defp secure_compare(_left, _right), do: false
end
