defmodule FSNotify do
  @moduledoc """
  A GenServer that can watch for filesystem events and send messages
  to another process when they are received. For information about
  messages that it sends, see `t:message/0`.
  """

  @type t() :: GenServer.name()

  @type message() ::
          {:fsnotify_event, path :: String.t(), ops :: MapSet.t(op())}
          | {:fsnotify_error, error_message :: String.t()}
  @type op() :: :create | :write | :remove | :rename | :chmod

  @type start_option() :: {:name, t()} | {:receiver, Process.dest()}

  use GenServer

  @doc """
  Starts a new monitor. A single monitor can watch for events in
  multiple files and directories, so one is generally enough for a lot
  of use cases.

  ## Options

    * `:name` - the name to register the GenServer under

    * `:receiver` - the process to send events and errors to (defaults
      to the calling process; should be present if running under a
      supervisor)
  """
  @spec start_link([start_option()]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    opts = Keyword.put_new(opts, :receiver, self())
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers a path to be watched by the monitor.
  """
  @spec add_watch(t(), Path.t()) :: :ok | {:error, String.t()}
  def add_watch(fsnotify, path) do
    GenServer.call(fsnotify, {:add_watch, path})
  end

  @doc """
  Removes a path that was previously registered to be watched by the
  monitor.
  """
  @spec remove(t(), Path.t()) :: :ok | {:error, String.t()}
  def remove(fsnotify, path) do
    GenServer.call(fsnotify, {:remove, path})
  end

  @doc """
  Returns, in no particular order, all paths registered to be watched
  by the monitor.
  """
  @spec watch_list(t()) :: [path] when path: String.t()
  def watch_list(fsnotify) do
    GenServer.call(fsnotify, :watch_list)
  end

  @doc """
  Stops the monitor, causing the process to shutdown cleanly.
  """
  @spec stop(t()) :: :ok
  def stop(fsnotify) do
    GenServer.cast(fsnotify, :stop)
  end

  @impl true
  def init(opts) do
    opts = Keyword.validate!(opts, [:receiver])

    executable = Path.join(:code.priv_dir(:fsnotify), "fsnotify")

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        packet: 2
      ])

    {:ok,
     %{
       receiver: Keyword.fetch!(opts, :receiver),
       port: port
     }}
  end

  @impl true
  def handle_call({:add_watch, path}, _from, state) do
    reply = send_command(state.port, "add_watch #{path}")
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:remove, path}, _from, state) do
    reply = send_command(state.port, "remove #{path}")
    {:reply, reply, state}
  end

  @impl true
  def handle_call(:watch_list, _from, state) do
    reply = send_command(state.port, "watch_list")
    {:reply, reply, state}
  end

  @impl true
  def handle_cast(:stop, state) do
    Port.close(state.port)
    {:stop, {:shutdown, :stopped}, state}
  end

  @impl true
  def handle_info({_port, {:data, <<0::8*8, data::binary>>}}, state) do
    send(state.receiver, data_to_message(JSON.decode!(data)))
    {:noreply, state}
  end

  defp send_command(port, command) do
    id = :erlang.unique_integer([:positive])
    Port.command(port, <<id::8*8-big, command::binary>>)

    receive do
      {^port, {:data, <<^id::8*8-big, data::binary>>}} ->
        data_to_reply(JSON.decode!(data))
    after
      1000 -> {:error, :timeout}
    end
  end

  defp data_to_reply("ok"), do: :ok
  defp data_to_reply(%{"OK" => val}), do: {:ok, val}
  defp data_to_reply(%{"Err" => err}), do: {:error, err}
  defp data_to_reply(data), do: data

  defp data_to_message(%{"Name" => name, "Op" => op}), do: {:fsnotify_event, name, op_to_set(op)}
  defp data_to_message(%{"Err" => err}), do: {:fsnotify_error, err}

  defp op_to_set(op) do
    <<chmod::1, rename::1, remove::1, write::1, create::1>> = <<op::5>>
    flags = [chmod: chmod, rename: rename, remove: remove, write: write, create: create]

    for {n, 1} <- flags, into: MapSet.new(), do: n
  end
end
