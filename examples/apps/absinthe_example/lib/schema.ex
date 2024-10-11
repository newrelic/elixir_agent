defmodule AbsintheExample.Schema do
  use Absinthe.Schema

  query do
    field :echo, :string do
      arg :this, :string
      resolve &AbsintheExample.Resolvers.echo/3
    end

    field :one, :one_thing do
      resolve &AbsintheExample.Resolvers.one/3
    end
  end

  object :one_thing do
    field :two, :two_thing
  end

  object :two_thing do
    field :three, :integer do
      resolve &AbsintheExample.Resolvers.three/3
    end
  end
end
