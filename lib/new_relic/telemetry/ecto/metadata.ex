defmodule NewRelic.Telemetry.Ecto.Metadata do
  @moduledoc false

  @postgrex_insert ~r/INSERT INTO "(?<table>\w+)"/
  @postgrex_create_table ~r/CREATE TABLE( IF NOT EXISTS)? "(?<table>\w+)"/
  @postgrex_update ~r/UPDATE "(?<table>\w+)"/
  def parse(%{
        source: table,
        query: query,
        result: {:ok, %{__struct__: Postgrex.Result, command: command}}
      }) do
    table =
      case {table, command} do
        {nil, :insert} -> capture(@postgrex_insert, query, "table")
        {nil, :create_table} -> capture(@postgrex_create_table, query, "table")
        {nil, :update} -> capture(@postgrex_update, query, "table")
        {nil, _} -> "other"
        {table, _} -> table
      end

    operation =
      case command do
        operation when is_atom(operation) -> operation
        [:rollback, :release] -> :rollback
        _ -> "other"
      end

    {"Postgres", table, operation}
  end

  @myxql_insert ~r/INSERT INTO `(?<table>\w+)`/
  @myxql_select ~r/FROM `(?<table>\w+)`/
  @myxql_create_table ~r/CREATE TABLE( IF NOT EXISTS)? `(?<table>\w+)`/
  @myxql_update ~r/UPDATE `(?<table>\w+)`/
  def parse(%{
        query: query,
        result: {:ok, %{__struct__: MyXQL.Result}}
      }) do
    {operation, table} =
      case query do
        "SELECT" <> _ -> {"select", capture(@myxql_select, query, "table")}
        "INSERT" <> _ -> {"insert", capture(@myxql_insert, query, "table")}
        "UPDATE" <> _ -> {"update", capture(@myxql_update, query, "table")}
        "CREATE TABLE" <> _ -> {"create_table", capture(@myxql_create_table, query, "table")}
        "begin" -> {:begin, "other"}
        "commit" -> {:commit, "other"}
        _ -> {"other", "other"}
      end

    {"MySQL", table, operation}
  end

  def parse(%{result: {:error, _}}), do: :ignore

  def parse(_) do
    raise "Unsupported ecto adapter"
  end

  def capture(regex, query, match) do
    Regex.named_captures(regex, query)[match]
  end
end
