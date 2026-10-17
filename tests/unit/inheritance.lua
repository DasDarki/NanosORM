Package.Require("init.lua")
local ORM = NanosORM
local Agg, Expr = ORM.Agg, ORM.Expr
local function sync(fn) local r fn(function(...) r = table.pack(...) end) if r == nil then return nil end return table.unpack(r, 1, r.n) end
local function raw(sql) local p = io.popen("sqlite3 sti.db \"" .. sql .. "\" 2>&1") local o = p:read("a"):gsub("%s+$", "") p:close() return o end

local Garage = ORM.entity("Garage")
  :column("id", "integer"):id()
  :column("name", "string")
  :oneToMany("cars", "Car", "garage")
  :build()
local Vehicle = ORM.entity("Vehicle")
  :inheritance("single", "kind")
  :abstract()
  :column("id", "integer"):id()
  :column("name", "string")
  :manyToOne("owner", "Garage"):nullable()
  :build()
local Car = ORM.entity("Car"):extends(Vehicle)
  :column("doors", "integer")
  :manyToOne("garage", "Garage"):nullable()
  :build()
local SportsCar = ORM.entity("SportsCar"):extends(Car):discriminatorValue("sports")
  :column("topSpeed", "integer")
  :build()
local Truck = ORM.entity("Truck"):extends(Vehicle)
  :column("payload", "number")
  :build()

check("own table rejected", pcall(function() ORM.entity("Bike", "bike"):extends(Vehicle):build() end), false)
check("duplicate discriminator rejected", pcall(function() ORM.entity("Van"):extends(Vehicle):discriminatorValue("car"):build() end), false)

os.remove("sti.db")
local em = ORM.connect(DatabaseEngine.SQLite, "sti.db")
check("schema", sync(function(cb) em:createSchema(cb) end), true)
print("   " .. raw(".schema vehicle"))
check("only one table", raw("select count(*) from sqlite_master where type = 'table' and name in ('vehicle', 'car', 'truck', 'sports_car')"), "1")

local abstractRoot = Vehicle.new() abstractRoot.name = "x"
em:persist(abstractRoot)
local okAbstract, errAbstract = sync(function(cb) em:flush(cb) end)
check("abstract root cannot be persisted", okAbstract, false)
print("   " .. tostring(errAbstract))
em:detach(abstractRoot)

local garage = Garage.new() garage.name = "main"
local car = Car.new() car.name = "golf" car.doors = 5 car.garage = garage car.owner = garage
local sports = SportsCar.new() sports.name = "f40" sports.doors = 2 sports.topSpeed = 320
local truck = Truck.new() truck.name = "actros" truck.payload = 18.5
em:persist(garage) em:persist(car) em:persist(sports) em:persist(truck)
check("flush", sync(function(cb) em:flush(cb) end), true)
check("rows", raw("select kind || ':' || ifnull(doors, '-') || ':' || ifnull(top_speed, '-') || ':' || ifnull(payload, '-') from vehicle where name = 'golf'") .. " " .. raw("select kind || ':' || top_speed from vehicle where name = 'f40'") .. " " .. raw("select kind || ':' || payload from vehicle where name = 'actros'"), "car:5:-:- sports:320 truck:18.5")

print("-- polymorphic loading")
local em2 = ORM.connect(DatabaseEngine.SQLite, "sti.db")
local all = sync(function(cb) em2:getRepository(Vehicle):query(nil, { orderBy = { "name" } }, cb) end)
check("all vehicles", #all, 3)
local byName = {}
for _, v in ipairs(all) do byName[v.name] = v end
check("classes", getmetatable(byName.golf).__name .. "," .. getmetatable(byName.f40).__name .. "," .. getmetatable(byName.actros).__name, "Car,SportsCar,Truck")
check("subclass fields loaded", byName.f40.topSpeed, 320)
check("metadata of loaded subclass", ORM.getMetadata(byName.f40).className, "SportsCar")
local cars = sync(function(cb) em2:getRepository(Car):findAll(cb) end)
check("car query includes subclasses", #cars, 2)
check("car identity shared with root query", (cars[1] == byName.golf or cars[1] == byName.f40) and (cars[2] == byName.golf or cars[2] == byName.f40), true)
check("sports only", sync(function(cb) em2:getRepository(SportsCar):count(nil, cb) end), 1)
check("trucks only", sync(function(cb) em2:getRepository(Truck):count(nil, cb) end), 1)
check("find through root", sync(function(cb) em2:find(Vehicle, truck.id, cb) end) == byName.actros, true)
check("find wrong subclass", sync(function(cb) em2:find(Car, truck.id, cb) end), nil)
local em3 = ORM.connect(DatabaseEngine.SQLite, "sti.db")
check("find wrong subclass unloaded", sync(function(cb) em3:find(Car, truck.id, cb) end), nil)
check("find subclass unloaded", getmetatable(sync(function(cb) em3:find(Car, sports.id, cb) end)).__name, "SportsCar")

print("-- references and relations")
local em4 = ORM.connect(DatabaseEngine.SQLite, "sti.db")
local g = sync(function(cb) em4:find(Garage, garage.id, cb) end)
check("load cars of garage", sync(function(cb) em4:load(g, { "cars" }, cb) end), true)
check("garage cars", g.cars:size(), 1)
local em5 = ORM.connect(DatabaseEngine.SQLite, "sti.db")
local ref = em5:getReference(Vehicle, sports.id)
check("reference is root class", getmetatable(ref).__name, "Vehicle")
local loaded = sync(function(cb) em5:getRepository(Vehicle):findBy({ id = sports.id }, cb) end)
check("reference retyped on load", getmetatable(ref).__name .. "/" .. tostring(ref == loaded[1]), "SportsCar/true")
check("retyped fields", ref.topSpeed, 320)
ref.topSpeed = 330
check("retyped tracked", ORM.isDirty(ref), true)
check("update subclass", sync(function(cb) em5:flush(cb) end), true)
check("updated", raw("select top_speed from vehicle where id = " .. sports.id), "330")
local withOwner = sync(function(cb) em5:getRepository(Vehicle):query({ ["owner.name"] = "main" }, { with = { "owner" } }, cb) end)
check("relation path on root", #withOwner, 1)

print("-- criteria, aggregate, remove")
local fast = sync(function(cb) em5:getRepository(SportsCar):findBy({ topSpeed = Expr.gt(300) }, cb) end)
check("subclass column criteria", #fast, 1)
local kinds = sync(function(cb) em5:getRepository(Vehicle):aggregate({ select = { n = Agg.count() } }, cb) end)
check("root aggregate", kinds[1].n, 3)
local carCount = sync(function(cb) em5:getRepository(Car):aggregate({ select = { n = Agg.count(), doors = Agg.sum("doors") } }, cb) end)
check("subclass aggregate filtered", carCount[1].n .. "/" .. carCount[1].doors, "2/7")
local t = sync(function(cb) em5:find(Truck, truck.id, cb) end)
em5:remove(t)
check("remove subclass", sync(function(cb) em5:flush(cb) end), true)
check("removed", raw("select count(*) from vehicle"), "2")

print("-- migration diff in sync")
local diff = sync(function(cb) em:getSchemaTool():getMigrationSql(cb) end)
check("diff empty", diff and #diff.up, 0)
