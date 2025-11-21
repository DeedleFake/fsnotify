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
          | {:fsnotify_stop, t()}
  @type op() :: :create | :write | :remove | :rename | :chmod

  @type start_option() :: {:name, t()} | {:watches, [Path.t()]}

  use GenServer

  @doc """
  Starts a new monitor. A single monitor can watch for events in
  multiple files and directories, so one is generally enough for a lot
  of use cases.

  ## Options

    * `:name` - the name to register the GenServer under (required)

    * `:watches` - an initial set of watches to add; failure to add
      any of them is considered fatal
  """
  @spec start_link([start_option()]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
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

  @doc """
  Subscribes the current process to events from the given monitor. See
  `t:message/0` for messages that are sent to subscribers.

  The fsnotify argument must be the name that the monitor was started
  with, not a PID.

  If the same process subscribes multiple times, it must unsubscribe
  the same number of times in order to stop receiving events. It will
  not receive duplicate events, however.

  Note that subscriptions are tracked externally to the monitor,
  meaning that if the monitor stops and then a new monitor is started
  with the same name, any processes that were already subscribed to
  the old monitor will receive events from the new one.
  """
  @spec subscribe(t()) :: :ok
  def subscribe(fsnotify) do
    :pg.join(FSNotify.Subscribers, fsnotify, [self()])
  end

  @doc """
  Unsubscribes the current process from the given monitor.
  """
  @spec unsubscribe(t()) :: :ok
  def unsubscribe(fsnotify) do
    :pg.leave(FSNotify.Subscribers, fsnotify, [self()])
  end

  @impl true
  def init(opts) do
    opts = Keyword.validate!(opts, [:name, watches: []])

    executable = Path.join(:code.priv_dir(:fsnotify), "fsnotify")

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        packet: 2
      ])

    {:ok,
     %{
       port: port,
       name: Keyword.fetch!(opts, :name)
     }, {:continue, {:add_initial_watches, opts[:watches]}}}
  end

  @impl true
  def handle_continue({:add_initial_watches, watches}, state) when is_list(watches) do
    for watch <- watches do
      :ok = send_command(state.port, :add_watch, watch)
    end

    {:noreply, state}
  end

  @impl true
  def handle_call({:add_watch, path}, _from, state) do
    reply = send_command(state.port, :add_watch, path)
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:remove, path}, _from, state) do
    reply = send_command(state.port, :remove, path)
    {:reply, reply, state}
  end

  @impl true
  def handle_call(:watch_list, _from, state) do
    reply = send_command(state.port, :watch_list)
    {:reply, reply, state}
  end

  @impl true
  def handle_cast(:stop, state) do
    Port.close(state.port)
    broadcast(state.name, {:fsnotify_stop, state.name})
    {:stop, {:shutdown, :stopped}, state}
  end

  @impl true
  def handle_info({_port, {:data, <<0::8*8, data::binary>>}}, state) do
    broadcast(state.name, data_to_message(JSON.decode!(data)))
    {:noreply, state}
  end

  defp send_command(port, command, arg \\ nil) do
    id = :erlang.unique_integer([:positive])
    Port.command(port, <<id::8*8-big, "#{command} #{arg}">>)

    receive do
      {^port, {:data, <<^id::8*8-big, data::binary>>}} ->
        data_to_reply(JSON.decode!(data))
    after
      1000 -> {:error, :timeout}
    end
  end

  defp broadcast(name, msg) do
    subscribers =
      :pg.get_members(FSNotify.Subscribers, name)
      |> Stream.uniq()

    for sub <- subscribers do
      send(sub, msg)
    end

    :ok
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
