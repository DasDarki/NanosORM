Package.Require("init.lua")
local ORM = NanosORM
local Money, Currency, Expr = ORM.Money, ORM.Currency, ORM.Expr
local function sync(fn) local r fn(function(...) r = table.pack(...) end) if r == nil then return nil end return table.unpack(r, 1, r.n) end
local function raw(sql) local p = io.popen("sqlite3 documentation.db \"" .. sql .. "\" 2>&1") local o = p:read("a"):gsub("%s+$", "") p:close() return o end

Currency.setDefault(Currency.of("EUR"))

local Point = {}
Point.__index = Point
Point.__name = "Point"
function Point.new(x, y) return setmetatable({ x = x, y = y }, Point) end

ORM.registerType("Point", function(column)
  return {
    getSqlType = function(self, platform) return "VARCHAR(64)" end,
    toDatabase = function(self, value, platform) return value.x .. "," .. value.y end,
    fromDatabase = function(self, raw, platform)
      local x, y = string.match(tostring(raw), "^(.-),(.-)$")
      return x and Point.new(tonumber(x), tonumber(y)) or nil
    end
  }
end, Point)

local Rank = { Member = 1, Officer = 2, Leader = 3 }

local Player = {}
Player.__index = Player
Player.__name = "Player"
setmetatable(Player, { __index = ORM.Model })
function Player:greet() return "Hello " .. self.name end
function Player:onPreUpdate()
  ORM.Model.onPreUpdate(self)
  if self.level > 100 then
    error("level cannot exceed 100")
  end
end

ORM.entity(Player)
  :column("playerID", "Uuid"):id()
  :column("name", "string"):length(32)
  :column("level", "integer")
  :column("rank", Rank)
  :column("spawn", "Point", true)
  :column("settings", "Json", true)
  :column("bank", "Money"):currency("EUR")
  :column("steamId", "SteamId", true)
  :build()

os.remove("documentation.db")
local em = ORM.connect(DatabaseEngine.SQLite, "documentation.db")
check("schema", sync(function(cb) em:createSchema(cb) end), true)

local player = setmetatable({ name = "Alice", level = 1, rank = Rank.Officer, bank = Money.of(100), spawn = Point.new(3, 4) }, Player)
player.settings = ORM.Json.new({ volume = 0.5 })
player.steamId = ORM.SteamId.fromSteam64("76561198000000001")
em:persist(player)
check("uuid id generated on persist", player.playerID ~= nil and player.playerID:getVersion(), 7)
check("uuid parse round trip", ORM.Uuid.parse(player.playerID:toString()) == player.playerID, true)
check("flush", sync(function(cb) em:flush(cb) end), true)
check("own class keeps methods", player:greet(), "Hello Alice")
check("created at set by model", player.createdAt ~= nil, true)
check("enum stored by name", raw("select rank from player"), "Officer")
check("custom type stored", raw("select spawn from player"), "3,4")

local updates = {}
local unsubscribe = em:on("postUpdate", function(entity, manager, changes)
  if changes.bank ~= nil then
    table.insert(updates, changes.bank.old:format() .. " -> " .. changes.bank.new:format())
  end
end, Player)

player.settings:get().volume = 0.8
player.bank = player.bank:plus(Money.of(50))
local changedFields = {}
for field in pairs(ORM.getChanges(player)) do table.insert(changedFields, field) end
table.sort(changedFields)
check("getChanges lists json and money", table.concat(changedFields, ","), "bank,settings")
check("flush update", sync(function(cb) em:flush(cb) end), true)
check("listener received changes", updates[1], "100.00 € -> 150.00 €")
unsubscribe()

player.level = 101
local ok, err = sync(function(cb) em:flush(cb) end)
check("pre update hook aborts flush", ok, false)
player.level = 50
check("flush after fix", sync(function(cb) em:flush(cb) end), true)

local fresh = ORM.connect(DatabaseEngine.SQLite, "documentation.db")
local loaded = sync(function(cb) fresh:getRepository(Player):findOneBy({ name = "Alice" }, cb) end)
check("custom type loaded", loaded.spawn.x + loaded.spawn.y, 7)
check("enum loaded", loaded.rank, Rank.Officer)
check("json loaded", loaded.settings:get().volume, 0.8)
check("steam id loaded", loaded.steamId:toString() ~= nil, true)
check("criteria with value type", #sync(function(cb) fresh:getRepository(Player):findBy({ bank = Expr.gte(Money.of(150)) }, cb) end), 1)

local result
fresh:transactional(function(manager, done)
  manager:find(Player, loaded.playerID, function(found)
    if found.bank:compareTo(Money.of(1000)) < 0 then
      return done("not enough money")
    end

    done(true)
  end)
end, function(committed, reason) result = { committed, reason } end)
check("transactional done with error text", result[1] == false and result[2], "not enough money")
