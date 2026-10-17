Package.GetName = function() return "nanos-orm" end
Package.Require("init.lua")
local function sync(fn) local r fn(function(...) r = table.pack(...) end) if r == nil then return nil end return table.unpack(r, 1, r.n) end
local function tables(db) local p = io.popen("sqlite3 " .. db .. " '.tables' 2>&1") local o = p:read("a"):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "") p:close() return o end
local function runAs(packageName, code)
  local chunk = assert(load(code, "@" .. packageName .. "/Server/Index.lua"))
  return chunk()
end

local a = runAs("pkg-a", [[
  local Item = NanosORM.entity("Item", "a_item"):column("id", "integer"):id():column("weight", "number"):build()
  local em = NanosORM.connect(DatabaseEngine.SQLite, "scope-a.db")
  return { Item = Item, em = em }
]])
local b = runAs("pkg-b", [[
  local Item = NanosORM.entity("Item", "b_item"):column("id", "integer"):id():column("color", "string"):build()
  local Shelf = NanosORM.entity("Shelf"):column("id", "integer"):id():oneToMany("items", "Item", "shelf"):build()
  NanosORM.entity("Crate"):column("id", "integer"):id():manyToOne("item", "Item"):build()
  local em = NanosORM.connect(DatabaseEngine.SQLite, "scope-b.db")
  return { Item = Item, Shelf = Shelf, em = em, metadata = NanosORM.getMetadata("Item") }
]])
local both = runAs("pkg-c", [[
  local em = NanosORM.connect(DatabaseEngine.SQLite, "scope-c.db", 1, { packages = { "pkg-a" } })
  return em
]])
local tail = runAs("pkg-d", [[
  return NanosORM.connect(DatabaseEngine.SQLite, "scope-d.db")
]])
check("tail call falls back to all packages", tail:getPackageName() == nil and tail:managesSchemaOf(NanosORM.getMetadata(a.Item)), true)
local all = NanosORM.connect(DatabaseEngine.SQLite, "scope-all.db", 1, { packages = "*" })

check("em knows its package", a.em:getPackageName() .. "," .. b.em:getPackageName(), "pkg-a,pkg-b")
check("getMetadata resolves own package", b.metadata.tableName, "b_item")
check("relation target resolves in own package", NanosORM.getMetadata(b.Shelf):getRelation("items"):getTarget().tableName, "b_item")
for _, db in ipairs({ "scope-a.db", "scope-b.db", "scope-c.db", "scope-all.db" }) do os.remove(db) end
check("schema a", sync(function(cb) a.em:createSchema(cb) end), true)
check("schema b", sync(function(cb) b.em:createSchema(cb) end), true)
check("schema c", sync(function(cb) both:createSchema(cb) end), true)
check("only own tables in a", tables("scope-a.db"), "a_item")
check("only own tables in b", tables("scope-b.db"), "b_item crate shelf")
check("extra package in c", tables("scope-c.db"), "a_item")
check("all packages", sync(function(cb) all:createSchema(cb) end), true)
local allTables = tables("scope-all.db")
check("all tables", allTables:find("a_item") ~= nil and allTables:find("b_item") ~= nil and allTables:find("shelf") ~= nil, true)
local diff = sync(function(cb) b.em:getSchemaTool():getMigrationSql(cb) end)
check("diff of b ignores a", diff and #diff.up, 0)
local okDrop = sync(function(cb) b.em:dropSchema(cb) end)
check("drop b", okDrop, true)
check("drop leaves nothing of b", tables("scope-b.db"), "")
