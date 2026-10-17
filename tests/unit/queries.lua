Package.Require("init.lua")
local ORM = NanosORM
local Agg, Expr = ORM.Agg, ORM.Expr
local function sync(fn)
  local results
  fn(function(...) results = table.pack(...) end)
  if results == nil then return nil end
  return table.unpack(results, 1, results.n)
end

local Guild = ORM.entity("Guild")
  :column("id", "integer"):id()
  :column("name", "string")
  :oneToMany("members", "Member", "guild"):cascade("persist")
  :build()
local Member = ORM.entity("Member")
  :column("id", "integer"):id()
  :column("name", "string")
  :column("level", "integer")
  :column("joinedAt", "DateTime")
  :column("deletedAt", "DateTime", true):softDelete()
  :manyToOne("guild", "Guild"):nullable()
  :build()

os.remove("query.db")
local em = ORM.connect(DatabaseEngine.SQLite, "query.db")
check("schema", sync(function(cb) em:createSchema(cb) end), true)
local DateTime = ORM.DateTime
local base = DateTime.of and DateTime.of(2026, 1, 1) or DateTime.now()
local guilds = {}
for g = 1, 3 do
  local guild = Guild.new() guild.name = "g" .. g
  guild.members = {}
  for m = 1, g * 2 do
    local member = Member.new()
    member.name = "m" .. g .. "_" .. m
    member.level = m * 10
    member.joinedAt = base:addDays(g * 10 + m)
    member.guild = guild
    table.insert(guild.members, member)
  end
  em:persist(guild)
  guilds[g] = guild
end
check("flush", sync(function(cb) em:flush(cb) end), true)
em:remove(guilds[3].members[1])
check("soft delete one", sync(function(cb) em:flush(cb) end), true)

local repo = em:getRepository(Member)
print("-- aggregate")
local rows, err = sync(function(cb) repo:aggregate({
  select = { guild = "guild", members = Agg.count(), avgLevel = Agg.avg("level"), maxLevel = Agg.max("level"), lastJoin = Agg.max("joinedAt") },
  orderBy = { "members DESC" }
}, cb) end)
check("aggregate ok", rows ~= nil, true)
if rows == nil then print(err) end
check("groups", #rows, 3)
check("first group is guild 3", rows[1].guild == guilds[3], true)
check("soft deleted excluded", rows[1].members, 5)
check("count is integer", math.type(rows[1].members), "integer")
check("avg", rows[3].avgLevel, 15.0)
check("max", rows[1].maxLevel, 60)
check("max datetime converted", getmetatable(rows[1].lastJoin) == DateTime, true)

local having = sync(function(cb) repo:aggregate({
  select = { guildName = "guild.name", members = Agg.count() },
  having = { members = Expr.gte(4) },
  orderBy = { "guildName" }
}, cb) end)
check("having through relation path", #having == 2 and having[1].guildName .. "," .. having[2].guildName, "g2,g3")

local total = sync(function(cb) repo:aggregate({ select = { total = Agg.sum("level"), distinct = Agg.countDistinct("level") }, withDeleted = true }, cb) end)
check("sum without group", total[1].total, 30 + 100 + 210)
check("count distinct", total[1].distinct, 6)
local bad, badErr = sync(function(cb) repo:aggregate({ select = { x = "nope" } }, cb) end)
check("unknown field error", bad == nil and badErr ~= nil, true)
print("   " .. tostring(badErr))

print("-- query builder")
local qb = repo:createQueryBuilder():where({ level = Expr.gte(40) }):orWhere({ name = "m1_1" }):orderBy("level DESC", "name"):limit(3)
local result = sync(function(cb) qb:getResult(cb) end)
check("builder result", #result, 3)
check("builder order", result[1].level, 60)
local orCount = sync(function(cb) repo:createQueryBuilder():where({ level = Expr.gte(40) }):orWhere({ name = "m1_1" }):count(cb) end)
check("builder count with or", orCount, 5)
local deletedCount = sync(function(cb) repo:createQueryBuilder():withDeleted():count(cb) end)
check("builder count with deleted", deletedCount, 12)
local one = sync(function(cb) repo:createQueryBuilder():where({ ["guild.name"] = "g2" }):where({ level = 30 }):with("guild"):getOne(cb) end)
check("builder getOne", one and one.name, "m2_3")
local grouped = sync(function(cb) repo:createQueryBuilder():where({ level = Expr.lte(20) }):aggregate({ select = { guild = "guild", n = Agg.count() }, orderBy = { "n" } }, cb) end)
check("builder aggregate", #grouped, 3)

print("-- native")
local nrows, nerr = sync(function(cb) em:nativeQuery("SELECT name, level FROM member WHERE level > ? AND name <> 'x?' ORDER BY level DESC, name", { 50 }, cb) end)
check("native rows", nrows and #nrows, 1)
if nrows == nil then print(nerr) end
check("native question mark in string kept", nrows and nrows[1].name, "m3_6")
local ids = { guilds[1].members[1].id, guilds[1].members[2].id }
local ents = sync(function(cb) em:nativeQuery("SELECT * FROM member WHERE id IN (?) ORDER BY id", { ids }, { entity = Member, with = { "guild" } }, cb) end)
check("native entities", #ents, 2)
check("native identity map", ents[1] == guilds[1].members[1], true)
local fresh = ORM.connect(DatabaseEngine.SQLite, "query.db")
local fents = sync(function(cb) fresh:nativeQuery("SELECT * FROM member WHERE guild_id = ?", { guilds[2] }, { entity = Member }, cb) end)
check("native entity param and hydrate", #fents, 4)
check("native hydrated datetime", getmetatable(fents[1].joinedAt) == DateTime, true)
local byDate = sync(function(cb) fresh:nativeQuery("SELECT COUNT(*) AS n FROM member WHERE joined_at > ?", { base:addDays(30) }, cb) end)
check("native value object param", byDate[1].n, 6)
local changed = sync(function(cb) em:nativeExecute("UPDATE member SET level = level + 1 WHERE guild_id = ?", { guilds[1] }, cb) end)
check("native execute count", changed, 2)
local emptyIn = sync(function(cb) em:nativeQuery("SELECT * FROM member WHERE id IN (?)", { {} }, cb) end)
check("empty array matches nothing", #emptyIn, 0)
local _, tooMany = sync(function(cb) em:nativeQuery("SELECT ?", { 1, 2 }, cb) end)
check("too many params", tooMany ~= nil, true)
