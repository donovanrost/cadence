defmodule Cadence.Accounts.AttemptLimitTest do
  @moduledoc "The password-check throttle: backoff per account+address, account and address."
  use Cadence.DataCase, async: false

  @moduletag :capture_log

  alias Cadence.Accounts
  alias Cadence.Accounts.AttemptLimit

  setup do
    AttemptLimit.reset()
    on_exit(&AttemptLimit.reset/0)
    %{email: "guess-#{System.unique_integer([:positive])}@example.com"}
  end

  defp fail(email, ip, times), do: for(_ <- 1..times, do: AttemptLimit.failed(email, ip))

  test "five failures from one address are free; then each waits, doubling", %{email: email} do
    fail(email, "10.0.0.1", 5)
    assert AttemptLimit.check(email, "10.0.0.1") == :ok

    fail(email, "10.0.0.1", 1)
    assert AttemptLimit.check(email, "10.0.0.1") == {:error, {:too_many_attempts, 1}}

    fail(email, "10.0.0.1", 2)
    assert AttemptLimit.check(email, "10.0.0.1") == {:error, {:too_many_attempts, 4}}
  end

  test "the delay is capped (no lockout)", %{email: email} do
    fail(email, "10.0.0.1", 40)
    assert {:error, {:too_many_attempts, 300}} = AttemptLimit.check(email, "10.0.0.1")
  end

  test "one address's failures don't hold the account back elsewhere", %{email: email} do
    fail(email, "10.0.0.1", 8)
    assert {:error, _} = AttemptLimit.check(email, "10.0.0.1")
    assert AttemptLimit.check(email, "10.0.0.2") == :ok
  end

  test "guessing spread over many addresses holds the account back after 20", %{email: email} do
    for n <- 1..21, do: AttemptLimit.failed(email, "10.0.1.#{n}")
    assert {:error, {:too_many_attempts, _}} = AttemptLimit.check(email, "10.0.2.1")
  end

  test "one address trying many accounts is held back after 50" do
    for n <- 1..51, do: AttemptLimit.failed("spray-#{n}@example.com", "10.0.3.1")
    assert {:error, _} = AttemptLimit.check("someone-else@example.com", "10.0.3.1")
    assert AttemptLimit.check("someone-else@example.com", "10.0.3.2") == :ok
  end

  test "a success clears the account; clear/1 is the operator's unlock", %{email: email} do
    fail(email, "10.0.0.1", 8)
    AttemptLimit.succeeded(email, "10.0.0.1")
    assert AttemptLimit.check(email, "10.0.0.1") == :ok

    fail(email, "10.0.0.1", 8)
    AttemptLimit.clear(String.upcase(email))
    assert AttemptLimit.check(email, " #{email} ") == :ok
  end

  test "sign-in answers the same for an email no account has, and holds the right password back too",
       %{email: email} do
    for _ <- 1..6 do
      assert {:error, :invalid_credentials} = Accounts.sign_in(email, "wrong", ip: "10.0.0.9")
    end

    assert {:error, {:too_many_attempts, 1}} =
             Accounts.sign_in(email, "anything", ip: "10.0.0.9")

    # A held-back attempt doesn't count, so waiting always works.
    assert {:error, {:too_many_attempts, 1}} =
             Accounts.sign_in(email, "anything", ip: "10.0.0.9")
  end
end
