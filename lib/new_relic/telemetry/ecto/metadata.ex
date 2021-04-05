defmodule NewRelic.Telemetry.Ecto.Metadata do
  @moduledoc false

  def parse(%{result: {:ok, %{__struct__: Postgrex.Cursor}}}), do: :ignore

  def parse(%{
        query: query,
        result: {_ok_or_error, %{__struct__: struct}}
      })
      when struct in [Postgrex.Result, Postgrex.Error] do
    {"Postgres", parse_query(query)}
  end

  def parse(%{result: {:ok, %{__struct__: MyXQL.Cursor}}}), do: :ignore

  def parse(%{
        query: query,
        result: {_ok_or_error, %{__struct__: struct}}
      })
      when struct in [MyXQL.Result, MyXQL.Error] do
    {"MySQL", parse_query(query)}
  end

  def parse(%{
        query: query,
        repo: repo,
        result: {_ok_or_error, %{__struct__: _result_struct}}
      }) do
    [adaapter | _] = repo.__adapter__() |> Module.split() |> Enum.reverse()
    {adaapter, parse_query(query)}
  end

  def parse(%{result: {:ok, _}}), do: :ignore
  def parse(%{result: {:error, _}}), do: :ignore

  defp parse_query(query) do
    {operation, table} =
      case query do
        "SELECT" <> _ -> {"select", table_name(:select, query)}
        "INSERT" <> _ -> {"insert", table_name(:insert, query)}
        "UPDATE" <> _ -> {"update", table_name(:update, query)}
        "DELETE" <> _ -> {"delete", table_name(:delete, query)}
        "CREATE TABLE" <> _ -> {"create", table_name(:create, query)}
        "begin" -> {"begin", "other"}
        "commit" -> {"commit", "other"}
        "rollback" -> {"rollback", "other"}
        _ -> {"other", "other"}
      end

    {table, operation}
  end

  # Table name escaping
  #   Postgrex: "table"
  #   MyXQL: `table`
  #   Tds: [table]
  #   Exqlite: table
  @esc ~w(" ` [ ])

  @capture %{
    select: ~r/FROM (?<table>\S+)/,
    insert: ~r/INSERT INTO (?<table>\S+)/,
    update: ~r/UPDATE (?<table>\S+)/,
    delete: ~r/FROM (?<table>\S+)/,
    create: ~r/CREATE TABLE( IF NOT EXISTS)? (?<table>\S+)/
  }
  defp table_name(query_type, query) do
    Regex.named_captures(@capture[query_type], query)["table"]
    |> String.replace(@esc, "")
  end
end
