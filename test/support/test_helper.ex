defmodule TestHelper do
  # todo: refactor callers to take path not conn
  def request(module, conn) do
    Plug.Cowboy.http(module, [], port: 8000)

    url = 'http://localhost:8000#{conn.request_path}'
    headers = Enum.map(conn.req_headers, fn {k, v} -> {'#{k}', '#{v}'} end)
    {:ok, {{_, status, _}, _, body}} = :httpc.request(:get, {url, headers}, [], [])

    Plug.Cowboy.shutdown(Module.concat(module, HTTP))

    # todo: refactor callers nicer struct (this used to be conn)
    %{status: status, resp_body: to_string(body)}
  end

  def trigger_report(module) do
    Process.sleep(300)
    GenServer.call(module, :report)
  end

  def gather_harvest(harvester) do
    Process.sleep(300)
    harvester.gather_harvest
  end

  def restart_harvest_cycle(harvest_cycle) do
    Process.sleep(300)
    GenServer.call(harvest_cycle, :restart)
  end

  def pause_harvest_cycle(harvest_cycle) do
    GenServer.call(harvest_cycle, :pause)
  end

  def find_metric(metrics, name, call_count \\ 1)

  def find_metric(metrics, {name, scope}, call_count) do
    Enum.find(metrics, fn
      [%{name: ^name, scope: ^scope}, [^call_count, _, _, _, _, _]] -> true
      _ -> false
    end)
  end

  def find_metric(metrics, name, call_count) do
    Enum.find(metrics, fn
      [%{name: ^name}, [^call_count, _, _, _, _, _]] -> true
      _ -> false
    end)
  end
end
