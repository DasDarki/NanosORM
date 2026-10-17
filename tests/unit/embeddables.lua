Package.Require("init.lua")
local ORM = NanosORM
local function sync(fn)
  local results
  fn(function(...) results = table.pack(...) end)
  if results == nil then return nil end
  return table.unpack(results, 1, results.n)
end
local function raw(sql)
  local p = io.popen("sqlite3 embed.db \"" .. sql .. "\" 2>&1")
  local out = p:read("a"):gsub("%s+$", "")
  p:close()
  return out
end

local Address = ORM.embeddable("Address")
  :column("street", "string")
  :column("city", "string"):length(64)
  :column("zip", "integer", true)
  :build()
local House = ORM.entity("House")
  :column("id", "integer"):id()
  :column("name", "string")
  :embedded("address", Address)
  :embedded("billing", "Address", "bill_"):nullable()
  :index({ "address.city" })
  :build()

check("embeddable without id ok", pcall(function() ORM.embeddable("Bad"):column("x", "string"):id() end), false)
check("prefix clash detected", pcall(function() ORM.entity("Clash"):column("id", "integer"):id():embedded("a", Address, "p_"):embedded("b", Address, "p_"):build() end), false)

os.remove("embed.db")
local em = ORM.connect(DatabaseEngine.SQLite, "embed.db")
check("schema", sync(function(cb) em:createSchema(cb) end), true)
print("   " .. raw(".schema house"))

local h = House.new()
h.name = "villa"
em:persist(h)
check("non-nullable embedded created on persist", h.address ~= nil and getmetatable(h.address) == Address, true)
check("nullable embedded stays nil", h.billing, nil)
h.address.street = "Main"
h.address.city = "Berlin"
check("flush insert", sync(function(cb) em:flush(cb) end), true)
check("row", raw("select address_street || '/' || address_city || '/' || ifnull(address_zip, 'null') || '/' || ifnull(bill_city, 'null') from house"), "Main/Berlin/null/null")
check("clean after flush", ORM.isDirty(h), false)

print("-- change detection")
h.address.zip = 10115
check("inner change dirty", ORM.isDirty(h), true)
check("inner change field dirty", ORM.isDirty(h, "address"), true)
SqlLog = {}
check("flush inner change", sync(function(cb) em:flush(cb) end), true)
check("zip stored", raw("select address_zip from house"), "10115")
local update
for _, s in ipairs(SqlLog) do if s:match("^UPDATE") then update = s end end
print("   " .. tostring(update))
check("clean again", ORM.isDirty(h), false)
h.address.zip = 10115
check("same value not dirty", ORM.isDirty(h), false)

local b = Address.new()
b.street = "Bill"
b.city = "Hamburg"
h.billing = b
check("flush replace nullable", sync(function(cb) em:flush(cb) end), true)
check("billing stored", raw("select bill_street || '/' || bill_city from house"), "Bill/Hamburg")

print("-- loading")
local em2 = ORM.connect(DatabaseEngine.SQLite, "embed.db")
local loaded = sync(function(cb) em2:find(House, h.id, cb) end)
check("address loaded", loaded.address.city, "Berlin")
check("address class", getmetatable(loaded.address), Address)
check("billing loaded", loaded.billing.city, "Hamburg")
check("loaded clean", ORM.isDirty(loaded), false)
loaded.billing = nil
check("flush clear nullable", sync(function(cb) em2:flush(cb) end), true)
check("billing null", raw("select ifnull(bill_city, 'null') from house"), "null")
local em3 = ORM.connect(DatabaseEngine.SQLite, "embed.db")
local again = sync(function(cb) em3:find(House, h.id, cb) end)
check("nil billing loads as nil", again.billing, nil)

print("-- criteria")
local h2 = House.new() h2.name = "hut" h2.address.city = "Munich" h2.address.street = "Side"
em3:persist(h2)
sync(function(cb) em3:flush(cb) end)
local found = sync(function(cb) em3:getRepository(House):findBy({ ["address.city"] = "Munich" }, cb) end)
check("criteria by embedded path", #found == 1 and found[1].name, "hut")
local ordered = sync(function(cb) em3:getRepository(House):query(nil, { orderBy = { "address.city DESC" } }, cb) end)
check("order by embedded path", ordered[1].name, "hut")
check("index on embedded column", raw("select name from sqlite_master where type = 'index' and tbl_name = 'house' and name like 'idx%'"), "idx_house_address_city")

print("-- refresh")
again.address.city = "Changed"
raw("update house set address_city = 'Cologne' where id = " .. h.id)
check("refresh", sync(function(cb) em3:refresh(again, cb) end), true)
check("refreshed embedded", again.address.city, "Cologne")
check("refresh clean", ORM.isDirty(again), false)
