# NanosORM

An object-relational mapper for [nanos world](https://nanos.world) servers, inspired by Doctrine. Map your classes to tables once and
work with objects: NanosORM tracks your changes, writes them in one transaction and loads related objects for you.

It is written in [Nebra](https://nebra-lang.github.io) and usable from Nebra with annotations and from plain Lua with a builder API.
It works with the nanos world `Database` class and is tested on SQLite and PostgreSQL. MySQL support is implemented but not tested yet.

```nebra
@Entity
class PlayerModel extends Model
  @Id
  @Column(type = "integer")
  playerID: number? = nil

  @Column(unique = true)
  steamId: SteamId? = nil

  @Column(currency = "EUR")
  bank: Money = Money.of(0)

  @OneToMany(mappedBy = "owner", cascade = "persist")
  vehicles: Collection<VehicleModel> = new Collection()
end

local player = await em:getRepository(PlayerModel):findOneBy({ steamId = steamId })
player.bank = player.bank:plus(Money.of(100))
await em:flush()
```

```lua
local Player = NanosORM.entity("Player")
    :column("id", "integer"):id()
    :column("name", "string"):length(32):unique()
    :column("level", "integer")
    :build()

em:getRepository(Player):findBy({ level = NanosORM.Expr.gte(10) }, function(players, err)
    for _, player in ipairs(players) do
        player.level = player.level + 1
    end

    em:flush()
end)
```

## Features

- Entities with annotations (Nebra) or a builder (Lua), mapped superclasses, embeddables and single table inheritance
- Change tracking through metatables, identity map, unit of work with batched inserts
- ManyToOne, OneToMany, OneToOne and ManyToMany relations with cascade, orphan removal, lazy and eager loading
- Criteria with operators and relation paths, a query builder, aggregates and native SQL
- Transactions like Doctrine, nested and with a timeout, optimistic locking and soft delete
- Value types for nanos world servers: `DateTime`, `Duration`, `Decimal`, `Money`, `Uuid`, `SteamId`, `Json`, `Vector`, `Rotator`, `Color`
- Schema creation, automatic migration and versioned migrations with a server console command
- Lifecycle events and per package scoping when several packages use the ORM on one server

## Documentation

Everything is documented in the [wiki](https://github.com/DasDarki/NanosORM/wiki), with every topic shown for Nebra and for Lua.

## Installation

NanosORM runs as its own nanos world package named `nanos-orm`, which exports the global `NanosORM`.

1. Build it with `nebra build` and copy the `out` folder to `Packages/nanos-orm` of your server.
2. Add `"nanos-orm"` to `packages_requirements` in the `Package.toml` of your package.
3. For a Nebra package, also add the dependency for the types and annotations from the Nebra package registry:
   `nebra add @DasDarki/nanos-orm`.

See [Getting Started](https://github.com/DasDarki/NanosORM/wiki/Getting-Started) for the details.

## Examples

- [examples/nebra-gamemode](examples/nebra-gamemode): a game mode in Nebra with accounts, characters, jobs and an item inheritance
- [examples/lua-script](examples/lua-script): a plain Lua script package with houses, furniture and vehicles

## Development

```bash
nebra build          # compiles the ORM to out/
tests/run.sh         # runs all tests against SQLite, needs lua5.4 and the sqlite3 command line tool
tests/run.sh queries # runs the suites whose name contains "queries"
```

`tests/unit` holds the test suites, which run the compiled ORM with a mocked nanos world API. `tests/nebra` checks the annotations and
`defer` from Nebra code. `tests/smoke` is a package for a real nanos world server: build it, put it next to `nanos-orm` in `Packages`
and set the custom settings `engine` (`sqlite`, `postgresql` or `mysql`) and `connection` in the `Config.toml` of the server.

## License

[MIT](LICENSE)
