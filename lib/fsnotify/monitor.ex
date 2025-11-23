defmodule FSNotify.Monitor do
  @moduledoc false

  use GenServer

  @doc """
  Starts a new monitor. A single monitor can watch for events in
  multiple files and directories, so one is generally enough for a lot
  of use cases.
  """
  @spec start_link([FSNotify.start_option()]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
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
    Registry.dispatch(
      FSNotify.Supervisor.registry_name(name),
      :subscribers,
      fn subscribers ->
        subscribers = Stream.uniq(subscribers)

        for {sub, nil} <- subscribers do
          send(sub, msg)
        end
      end,
      parallel: true
    )

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
