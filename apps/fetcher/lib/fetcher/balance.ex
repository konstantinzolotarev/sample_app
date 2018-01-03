defmodule Fetcher.Balance do

  use GenServer
  require Logger


  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc false
  def init(state) do
    num = :rand.uniform(2)
    Logger.info("Got #{num}")
    if num > 1 do
      raise "Test exception"
    end
    {:ok, state}
  end

  def fail() do
    GenServer.call(__MODULE__, :fail)
  end

  def handle_call(:fail, _from, state), do: raise "Fail !"
end
