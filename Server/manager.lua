Package.Require("migrator.lua")
Package.Require("querybuilder.lua")

DB = {
  _VERSION = Package.GetVersion(),
  _MODELS = {},
  _M2M_TABLES = {},
  _nanosDB = nil,
  _isFinalized = false,

  NamingPolicy = function (name)
    name = name:gsub("ID", "Id")
    return name:gsub("%u", function(s)
      return "_" .. s:lower()
    end):sub(2)
  end
}

function DB.FinalizeModels()
  if #DB._ASSOC_FINALIZERS == 0 then
    return
  end

  for _, assoc in ipairs(DB._ASSOC_FINALIZERS) do
    assoc()
  end

  DB._isFinalized = true
end

function DB.Init(hostname, port, username, password, database)
  if DB._nanosDB ~= nil then
    error("Postgres Connection already initialized")
  end

  hostname = hostname or "localhost"
  port = port or 5432
  username = username or "postgres"
  password = password or "postgres"
  database = database or "postgres"

  DB._nanosDB = Database(DatabaseEngine.PostgreSQL, "host=" .. hostname .. " port=" .. port .. " user=" .. username .. " password=" .. password .. " dbname=" .. database)
  if DB._nanosDB == nil then
    return
  end

  DB._nanosDB:Execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";")
  DB._nanosDB:Execute("CREATE TABLE IF NOT EXISTS _orm__deleted_records (id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), deleted_at timestampz DEFAULT NOW(), original_table varchar(255), original_id TEXT, data jsonb);")

  DB.FinalizeModels()
end

function DB.Save(model, instance)
  if DB._nanosDB == nil then
    error("Postgres Connection not initialized")
  end

  DB.FinalizeModels()


end

function DB.Delete(model, instance, hard)
  if DB._nanosDB == nil then
    error("Postgres Connection not initialized")
  end

  DB.FinalizeModels()

  hard = hard or false


end

function DB.FindWhere(model, where, lazy)
  if DB._nanosDB == nil then
    error("Postgres Connection not initialized")
  end

  DB.FinalizeModels()

  lazy = lazy or false


end

function DB.FindOneWhere(model, where, lazy)
  if DB._nanosDB == nil then
    error("Postgres Connection not initialized")
  end

  DB.FinalizeModels()

  lazy = lazy or false

end

function DB.QueryBuilder(model)
  if DB._nanosDB == nil then
    error("Postgres Connection not initialized")
  end

  DB.FinalizeModels()

  return NewQueryBuilder(DB._nanosDB, model)
end

function DB.AutoMigrate()
  if DB._nanosDB == nil then
    error("Postgres Connection not initialized")
  end

  DB.FinalizeModels()

  AutoMigrateModels(DB._nanosDB, DB._MODELS)
end