defmodule NewRelic.Telemetry.Ecto.Metadata do
  @moduledoc false

  @postgrex_select ~r/FROM "(?<table>\w+)"/
  @postgrex_insert ~r/INSERT INTO "(?<table>\w+)"/
  @postgrex_update ~r/UPDATE "(?<table>\w+)"/
  @postgrex_delete ~r/FROM "(?<table>\w+)"/
  @postgrex_create_table ~r/CREATE TABLE( IF NOT EXISTS)? "(?<table>\w+)"/
  def parse(%{
        query: query,
        result: {_ok_or_error, %{__struct__: struct}}
      })
      when struct in [Postgrex.Result, Postgrex.Error] do
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
  def parse(%{
        query: query,
        result: {_ok_or_error, %{__struct__: struct}}
      })
      when struct in [MyXQL.Result, MyXQL.Error] do
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

  @tds_select ~r/FROM \[(?<table>\w+)\]/
  @tds_insert ~r/INSERT INTO \[(?<table>\w+)\]/
  @tds_update ~r/UPDATE \[(?<table>\w+)\]/
  @tds_delete ~r/FROM \[(?<table>\w+)\]/
  def parse(%{
        query: query,
        result: {_ok_or_error, %{__struct__: struct}}
      })
      when struct in [Tds.Result, Tds.Error] do
    {operation, table} =
      case query do
        "SELECT" <> _ -> {"select", capture(@tds_select, query, "table")}
        "INSERT" <> _ -> {"insert", capture(@tds_insert, query, "table")}
        "UPDATE" <> _ -> {"update", capture(@tds_update, query, "table")}
        "DELETE" <> _ -> {"delete", capture(@tds_delete, query, "table")}
        "begin" -> {"begin", "other"}
        "commit" -> {"commit", "other"}
        "rollback" -> {"rollback", "other"}
        _ -> {"other", "other"}
      end

    {"MSSQL", table, operation}
  end

  def parse(%{result: {:ok, %{__struct__: Postgrex.Cursor}}}), do: :ignore
  def parse(%{result: {:ok, %{__struct__: MyXQL.Cursor}}}), do: :ignore
  def parse(%{result: {:ok, nil}}), do: :ignore
  def parse(%{result: {:error, _}}), do: :ignore

  def capture(regex, query, match) do
    Regex.named_captures(regex, query)[match]
  end
end
