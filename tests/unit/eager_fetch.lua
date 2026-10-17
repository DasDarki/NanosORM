Package.Require("init.lua")
local ORM = NanosORM
local function sync(fn)
  local results
  fn(function(...) results = table.pack(...) end)
  if results == nil then return nil end
  return table.unpack(results, 1, results.n)
end

local Guild = ORM.entity("Guild")
  :column("id", "integer"):id()
  :column("name", "string")
  :oneToMany("members", "Member", "guild"):fetch("eager"):cascade("persist")
  :build()
local Member = ORM.entity("Member")
  :column("id", "integer"):id()
  :column("name", "string")
  :manyToOne("guild", "Guild"):inversedBy("members"):fetch("eager"):nullable()
  :manyToOne("parent", "Member"):fetch("eager"):nullable()
  :manyToOne("house", "House"):nullable()
  :build()
local House = ORM.entity("House")
  :column("id", "integer"):id()
  :column("street", "string")
  :build()

os.remove("eager.db")
local em = ORM.connect(DatabaseEngine.SQLite, "eager.db")
check("schema", sync(function(cb) em:createSchema(cb) end), true)
local g = Guild.new() g.name = "g"
local h = House.new() h.street = "s"
local boss = Member.new() boss.name = "boss" boss.guild = g
local m = Member.new() m.name = "m" m.guild = g m.parent = boss m.house = h
g.members = { boss, m }
em:persist(g) em:persist(h)
check("flush", sync(function(cb) em:flush(cb) end), true)

local function fresh() return ORM.connect(DatabaseEngine.SQLite, "eager.db") end

print("-- eager one-to-many from guild")
local em2 = fresh()
SqlLog = {}
local guilds = sync(function(cb) em2:getRepository(Guild):findAll(cb) end)
check("members initialized", guilds[1].members:isInitialized(), true)
check("member count", guilds[1].members:size(), 2)
check("queries", #SqlLog - 1, 2)

local child
for _, mm in ipairs(guilds[1].members:toArray()) do if mm.name == "m" then child = mm end end
check("parent eager loaded", ORM.isInitialized(child.parent), true)
check("house stays lazy", ORM.isInitialized(child.house), false)

print("-- eager many-to-one from member")
local em3 = fresh()
SqlLog = {}
local mm = sync(function(cb) em3:find(Member, child.id, cb) end)
check("guild joined", ORM.isInitialized(mm.guild), true)
check("guild members loaded", mm.guild.members:isInitialized(), false)
check("parent joined", ORM.isInitialized(mm.parent), true)
check("one query", #SqlLog - 1, 1)


print("-- eager disabled")
local em4 = fresh()
local plain = sync(function(cb) em4:getRepository(Member):query({ name = "m" }, { eager = false }, cb) end)
check("guild lazy", ORM.isInitialized(plain[1].guild), false)

print("-- load expands eager of targets")
local em5 = fresh()
local lazy = sync(function(cb) em5:getRepository(Member):query({ name = "m" }, { eager = false }, cb) end)
check("load parent", sync(function(cb) em5:load(lazy, { "parent" }, cb) end), true)
check("parent loaded", ORM.isInitialized(lazy[1].parent), true)
check("eager guild of parent via load", ORM.isInitialized(lazy[1].parent.guild), true)
check("back reference skipped", lazy[1].parent.guild.members:isInitialized(), false)
