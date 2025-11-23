defmodule FSNotify do
  @moduledoc """
  A monitor that can watch for filesystem events and send messages to
  another process when they are received. For information about
  messages that it sends, see `t:message/0`.

  ## Options

    * `:name` - the name to register the GenServer under (required)

    * `:watches` - an initial set of watches to add; failure to add
      any of them is considered fatal
  """

  @doc false
  defdelegate child_spec(spec), to: FSNotify.Supervisor

  @type name() :: GenServer.name()

  @type message() ::
          {:fsnotify_event, path :: String.name(), ops :: MapSet.t(op())}
          | {:fsnotify_error, error_message :: String.name()}
          | {:fsnotify_stop, name()}
  @type op() :: :create | :write | :remove | :rename | :chmod

  @type start_option() :: {:name, name()} | {:watches, [Path.name()]}

  @doc """
  Registers a path to be watched by the monitor.
  """
  @spec add_watch(name(), Path.name()) :: :ok | {:error, String.name()}
  def add_watch(name, path) do
    GenServer.call(name, {:add_watch, path})
  end

  @doc """
  Removes a path that was previously registered to be watched by the
  monitor.
  """
  @spec remove(name(), Path.name()) :: :ok | {:error, String.name()}
  def remove(name, path) do
    GenServer.call(name, {:remove, path})
  end

  @doc """
  Returns, in no particular order, all paths registered to be watched
  by the monitor.
  """
  @spec watch_list(name()) :: [path] when path: String.name()
  def watch_list(name) do
    GenServer.call(name, :watch_list)
  end

  @doc """
  Stops the monitor, causing the process to shutdown cleanly.
  """
  @spec stop(name()) :: :ok
  def stop(name) do
    GenServer.cast(name, :stop)
  end

  @doc """
  Subscribes the current process to events from the given monitor. See
  `t:message/0` for messages that are sent to subscribers.

  A process subscribing when it is already subscribed has no effect.

  Note that subscriptions are tracked externally to the monitor,
  meaning that if the monitor stops and then a new monitor is started
  with the same name, any processes that were already subscribed to
  the old monitor will receive events from the new one.
  """
  @spec subscribe(name()) :: :ok
  def subscribe(name) do
    Registry.register(FSNotify.Supervisor.registry_name(name), :subscribers, nil)
    :ok
  end

  @doc """
  Unsubscribes the current process from the given monitor.
  """
  @spec unsubscribe(name()) :: :ok
  def unsubscribe(name) do
    Registry.unregister(FSNotify.Supervisor.registry_name(name), :subscribers)
    :ok
  end
end
