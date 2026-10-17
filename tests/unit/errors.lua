Package.Require("init.lua")
local ORM = NanosORM
local Money = ORM.Money
local function sync(fn) local r fn(function(...) r = table.pack(...) end) if r == nil then return nil end return table.unpack(r, 1, r.n) end
local function raw(sql) local p = io.popen("sqlite3 errors.db \"" .. sql .. "\" 2>&1") local o = p:read("a"):gsub("%s+$", "") p:close() return o end
local Wallet = ORM.entity("Wallet"):column("id", "integer"):id():column("balance", "Money"):currency("EUR")
  :column("level", "integer"):build()
os.remove("errors.db")
local em = ORM.connect(DatabaseEngine.SQLite, "errors.db")
check("schema", sync(function(cb) em:createSchema(cb) end), true)
local ok0 = Wallet.new({ balance = Money.of(1, ORM.Currency.of("EUR")), level = 1 })
em:persist(ok0)
check("first insert", sync(function(cb) em:flush(cb) end), true)
local bad = Wallet.new({ balance = Money.of(5), level = 2 })
em:persist(bad)
SqlLog = {}
local done, err = sync(function(cb) em:flush(cb) end)
check("conversion error reported to callback", done, false)
print("   " .. tostring(err))
local rolledBack = false
for _, q in ipairs(SqlLog) do if q == "ROLLBACK" then rolledBack = true end end
check("flush transaction rolled back", rolledBack, true)
em:detach(bad)
local again = Wallet.new({ balance = Money.of(2, ORM.Currency.of("EUR")), level = 3 })
em:persist(again)
check("next flush works", sync(function(cb) em:flush(cb) end), true)
check("rows", raw("select count(*) from wallet"), "2")
local fresh = ORM.connect(DatabaseEngine.SQLite, "errors.db")
fresh:on("postLoad", function() error("listener failed") end, Wallet)
local rows, loadErr = sync(function(cb) fresh:getRepository(Wallet):findAll(cb) end)
check("hydration error reported", rows == nil and loadErr ~= nil, true)
print("   " .. tostring(loadErr))
