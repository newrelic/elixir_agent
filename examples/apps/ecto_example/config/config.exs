use Mix.Config

config :ecto_example,
  http_port: 4001,
  ecto_repos: [EctoExample.PostgresRepo, EctoExample.MySQLRepo]

config :ecto_example, EctoExample.PostgresRepo,
  database: "example_db",
  username: "postgres",
  password: "password",
  hostname: "localhost",
  port: 5432

config :ecto_example, EctoExample.MySQLRepo,
  database: "example_db",
  username: "root",
  password: "password",
  hostname: "localhost",
  port: 3306
