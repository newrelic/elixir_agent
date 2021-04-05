defmodule NewRelic.Telemetry.Ecto.Metadata do
  @moduledoc false

  def parse(%{
        query: query,
        result: {_ok_or_error, %{__struct__: struct}}
      })
      when struct in [Postgrex.Result, Postgrex.Error] do
    parse_query(query, "Postgres")
  end

  def parse(%{
        query: query,
        result: {_ok_or_error, %{__struct__: struct}}
      })
      when struct in [MyXQL.Result, MyXQL.Error] do
    parse_query(query, "MySQL")
  end

  def parse(%{
        query: query,
        result: {_ok_or_error, %{__struct__: struct}}
      })
      when struct in [Exqlite.Result, Exqlite.Error] do
    parse_query(query, "SQLite3")
  end

  def parse(%{query: query, repo: repo, result: {_ok_or_error, _}}) do
    case repo.__adapter__() do
      Ecto.Adapters.Jamdb.Oracle -> parse_query(query, "Oracle")
      _ -> :ignore
    end
  end

  def parse(%{result: {:ok, %{__struct__: Postgrex.Cursor}}}), do: :ignore
  def parse(%{result: {:ok, %{__struct__: MyXQL.Cursor}}}), do: :ignore
  def parse(%{result: {:ok, %{__struct__: SQLite3.Cursor}}}), do: :ignore
  def parse(%{result: {:ok, nil}}), do: :ignore
  def parse(%{result: {:error, _}}), do: :ignore

  @postgrex_select ~r/FROM "(?<table>\w+)"/
  @postgrex_insert ~r/INSERT INTO "(?<table>\w+)"/
  @postgrex_update ~r/UPDATE "(?<table>\w+)"/
  @postgrex_delete ~r/FROM "(?<table>\w+)"/
  @postgrex_create_table ~r/CREATE TABLE( IF NOT EXISTS)? "(?<table>\w+)"/
  defp parse_query(query, "Postgres") do
    {operation, table} =
      case query do
        "SELECT" <> _ -> {"select", capture(@postgrex_select, query, "table")}
        "INSERT" <> _ -> {"insert", capture(@postgrex_insert, query, "table")}
        "UPDATE" <> _ -> {"update", capture(@postgrex_update, query, "table")}
        "DELETE" <> _ -> {"delete", capture(@postgrex_delete, query, "table")}
        "CREATE TABLE" <> _ -> {"create", capture(@postgrex_create_table, query, "table")}
        "begin" -> {"begin", "other"}
        "commit" -> {"commit", "other"}
        "rollback" -> {"rollback", "other"}
        _ -> {"other", "other"}
      end

    {"Postgres", table, operation}
  end

  @myxql_select ~r/FROM `(?<table>\w+)`/
  @myxql_insert ~r/INSERT INTO `(?<table>\w+)`/
  @myxql_update ~r/UPDATE `(?<table>\w+)`/
  @myxql_delete ~r/FROM `(?<table>\w+)`/
  @myxql_create_table ~r/CREATE TABLE( IF NOT EXISTS)? `(?<table>\w+)`/
  defp parse_query(query, "MySQL") do
    {operation, table} =
      case query do
        "SELECT" <> _ -> {"select", capture(@myxql_select, query, "table")}
        "INSERT" <> _ -> {"insert", capture(@myxql_insert, query, "table")}
        "UPDATE" <> _ -> {"update", capture(@myxql_update, query, "table")}
        "DELETE" <> _ -> {"delete", capture(@myxql_delete, query, "table")}
        "CREATE TABLE" <> _ -> {"create", capture(@myxql_create_table, query, "table")}
        "begin" -> {"begin", "other"}
        "commit" -> {"commit", "other"}
        "rollback" -> {"rollback", "other"}
        _ -> {"other", "other"}
      end

    {"MySQL", table, operation}
  end

  @sqlite3_select ~r/FROM (?<table>\w+)/
  @sqlite3_insert ~r/INSERT INTO (?<table>\w+)/
  @sqlite3_update ~r/UPDATE (?<table>\w+)/
  @sqlite3_delete ~r/FROM (?<table>\w+)/
  @sqlite3_create_table ~r/CREATE TABLE( IF NOT EXISTS)? (?<table>\w+)/
  defp parse_query(query, "SQLite3") do
    {operation, table} =
      case query do
        "SELECT" <> _ -> {"select", capture(@sqlite3_select, query, "table")}
        "INSERT" <> _ -> {"insert", capture(@sqlite3_insert, query, "table")}
        "UPDATE" <> _ -> {"update", capture(@sqlite3_update, query, "table")}
        "DELETE" <> _ -> {"delete", capture(@sqlite3_delete, query, "table")}
        "CREATE TABLE" <> _ -> {"create", capture(@sqlite3_create_table, query, "table")}
        "begin" -> {"begin", "other"}
        "commit" -> {"commit", "other"}
        "rollback" -> {"rollback", "other"}
        _ -> {"other", "other"}
      end

    {"SQLite3", table, operation}
  end

  @oracle_select ~r/FROM (?<table>[.\w]+)/
  @oracle_insert ~r/INSERT INTO (?<table>[.\w]+)/
  @oracle_update ~r/UPDATE (?<table>[.\w]+)/
  @oracle_delete ~r/FROM (?<table>[.\w]+)/
  @oracle_create_table ~r/CREATE TABLE (?<table>[.\w]+)/
  defp parse_query(query, "Oracle") do
    {operation, table} =
      case query do
        "SELECT" <> _ -> {"select", capture(@oracle_select, query, "table")}
        "INSERT" <> _ -> {"insert", capture(@oracle_insert, query, "table")}
        "UPDATE" <> _ -> {"update", capture(@oracle_update, query, "table")}
        "DELETE" <> _ -> {"delete", capture(@oracle_delete, query, "table")}
        "CREATE TABLE" <> _ -> {"create", capture(@oracle_create_table, query, "table")}
        "begin" -> {"begin", "other"}
        "commit" -> {"commit", "other"}
        "rollback" -> {"rollback", "other"}
        _ -> {"other", "other"}
      end

    {"Oracle", table, operation}
  end

  def capture(regex, query, match) do
    Regex.named_captures(regex, query)[match]
  end
end
