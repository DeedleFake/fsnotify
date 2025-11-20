defmodule ExnotifyPort do
  use GenServer

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    opts = Keyword.put_new(opts, :receiver, self())
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def add_watch(server, path) do
    GenServer.call(server, {:add_watch, path})
  end

  @impl true
  def init(opts) do
    opts = Keyword.validate!(opts, [:receiver])

    executable = Path.join(:code.priv_dir(:exnotify_port), "inotify")

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
    Port.command(state.port, "add_watch #{path}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({_port, {:data, data}}, state) do
    send(state.receiver, data_to_message(JSON.decode!(data)))
    {:noreply, state}
  end

  defp data_to_message(%{"Name" => name, "Op" => op}) do
    {:inotify_event, name, op}
  end

  defp data_to_message(%{"Err" => err}) do
    {:inotify_error, err}
  end
end
