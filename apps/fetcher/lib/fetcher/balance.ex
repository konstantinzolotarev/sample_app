defmodule Fetcher.Balance do
  use GenServer
  require Logger

  # Delay that will be used to reload balance
  @delay 600000
  @server Application.get_env(:fetcher, :server)

  defmodule State do

    @moduledoc false
    @doc false
    @opaque t :: %__MODULE__{balances: [map], timer: reference}
    defstruct balances: [], timer: nil
  end

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, %State{}, name: __MODULE__)


  @spec reload() :: :ok | {:error, term}
  def reload(), do: GenServer.cast(__MODULE__, :balance)

  @doc """
  Get balance for given currency id/symbol

  ## Example:
  ```elixir
  iex> Fetcher.Balance.available(331)
  0
  iex> Fetcher.Balance.available("ETH")
  0.001
  ```
  """
  @spec available(binary | number) :: number
  def available(currency), do: GenServer.call(__MODULE__, {:available, currency})

  @doc """
  Check if available balance of currency is greater or eq for requested amount
  """
  @spec enough?(binary | number, number) :: boolean
  def enough?(currency, balance), do: available(currency) >= balance

  @doc """
  Will load all info about currency state

  ## Example:
  ```elixir
  iex> Fetcher.Balance.get("BCH")
  %{Address: nil, Available: 0.0, BaseAddress: "", CurrencyId: 586,
  HeldForTrades: 0.00717021, PendingWithdraw: 0.0, Status: "OK",
  StatusMessage: nil, Symbol: "BCH", Total: 0.00717021, Unconfirmed: 0.0}

  iex> Fetcher.Balance.get("ETH")
  nil
  ```
  """
  @spec get(binary | number) :: map | nil
  def get(currency), do: GenServer.call(__MODULE__, {:get, currency})


  @doc false
  def init(state) do
    new_state = state
                |> load_balances()
                |> setup_timer()

    {:ok, new_state}
  end

  # Load balance for user
  def handle_cast(:balance, state) do
    new_state = state
                |> load_balances()
                |> cancel_timer()
                |> setup_timer()

    {:noreply, new_state}
  end

  # Load all details about given currency
  def handle_call({:get, currency}, _from, %State{balances: balances} = state) do
    {:reply, get_balance(balances, currency), state}
  end

  # Load only available balance
  def handle_call({:available, currency}, _from, %State{balances: balances} = state) do
    result = case get_balance(balances, currency) do
      %{Available: avail} -> avail
      _ -> 0.0
    end
    {:reply, result, state}
  end

  @doc false
  def handle_info(:balance, state) do
    new_state = state
                |> load_balances()
                |> cancel_timer()
                |> setup_timer()

    {:noreply, new_state}
  end


  defp make_http_request() do
    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        balance = Poison.decode!(body, keys: :atoms)
        {:ok, balance}
      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, "Not found"}
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  # Get balance map for given currency id
  defp get_balance(balances, currency) when is_number(currency) do
    balances
    |> Enum.find(fn (%{CurrencyId: symbol}) -> symbol == currency end)
  end
  # get balance map for given cyrrency symbol
  defp get_balance(balances, currency) when is_binary(currency) do
    balances
    |> Enum.find(fn (%{Symbol: symbol}) -> symbol == currency end)
  end
  defp get_balance(_, _), do: nil

  # load balance for current user
  # it iwll load all currencies with total balance greater than 0
  defp load_balances(%State{} = state) do
    Logger.debug("Loading user balance")
    case make_http_request() do
      {:ok, balances} ->
        result = balances |> Enum.filter(fn (%{Total: total}) -> total > 0 end)
        Logger.debug("User balance loaded #{inspect(result)}")
        %State{state | balances: result}
      {:error, _} ->
        Logger.error("Failed to load user balance")
        state
    end
  end

  # Set timer for next baalnce update
  defp setup_timer(state) do
    Logger.debug("Set new timer balance update #{@delay}")
    timer = Process.send_after(__MODULE__, :balance, @delay)
    %State{state | timer: timer}
  end

  # Cancel timer
  # This function needed here because balance might be updated not only
  # by timeout but also manually on new order creation.
  defp cancel_timer(%State{timer: nil} = state), do: state
  defp cancel_timer(%State{timer: timer_ref} = state) do
    Logger.debug("Cancel balance update timer")
    Process.cancel_timer(timer_ref)
    %State{state | timer: nil}
  end

end
