Package.Require("init.lua")
local ORM = NanosORM
local Agg = ORM.Agg
local function sync(fn) local r fn(function(...) r = table.pack(...) end) if r == nil then return nil end return table.unpack(r, 1, r.n) end
local function raw(sql) local p = io.popen("sqlite3 softdelete.db \"" .. sql .. "\" 2>&1") local o = p:read("a"):gsub("%s+$", "") p:close() return o end
local Owner = ORM.entity("Owner"):column("id", "integer"):id():column("name", "string"):oneToMany("pets", "Pet", "owner"):build()
local Pet = ORM.entity("Pet"):extends(ORM.SoftDeleteModel):column("id", "integer"):id():column("name", "string"):manyToOne("owner", "Owner"):build()
os.remove("softdelete.db")
local em = ORM.connect(DatabaseEngine.SQLite, "softdelete.db")
check("schema", sync(function(cb) em:createSchema(cb) end), true)
local owner = Owner.new({ name = "o" })
em:persist(owner)
local pets = {}
for i = 1, 3 do pets[i] = Pet.new({ name = "p" .. i, owner = owner }) em:persist(pets[i]) end
check("flush", sync(function(cb) em:flush(cb) end), true)
em:remove(pets[1])
check("soft remove", sync(function(cb) em:flush(cb) end), true)
check("row kept with deleted_at", raw("select count(*) from pet where deleted_at is not null"), "1")
check("isDeleted", pets[1]:isDeleted(), true)
local fresh = ORM.connect(DatabaseEngine.SQLite, "softdelete.db")
local repo = fresh:getRepository(Pet)
check("findAll filters", #sync(function(cb) repo:findAll(cb) end), 2)
check("count filters", sync(function(cb) repo:count(nil, cb) end), 2)
check("withDeleted", #sync(function(cb) repo:query(nil, { withDeleted = true }, cb) end), 3)
check("find filters", sync(function(cb) fresh:find(Pet, pets[1].id, cb) end), nil)
check("query builder filters", sync(function(cb) repo:createQueryBuilder():count(cb) end), 2)
check("aggregate filters", sync(function(cb) repo:aggregate({ select = { n = Agg.count() } }, cb) end)[1].n, 2)
local o = sync(function(cb) fresh:find(Owner, owner.id, cb) end)
sync(function(cb) fresh:load(o, { "pets" }, cb) end)
check("to-many relation filters", o.pets:size(), 2)
check("relation path filter", #sync(function(cb) fresh:getRepository(Owner):findBy({ ["pets.name"] = "p1" }, cb) end), 0)
local deleted = sync(function(cb) repo:query({ id = pets[1].id }, { withDeleted = true }, cb) end)[1]
deleted.deletedAt = nil
check("restore", sync(function(cb) fresh:flush(cb) end), true)
check("restored visible", sync(function(cb) ORM.connect(DatabaseEngine.SQLite, "softdelete.db"):getRepository(Pet):count(nil, cb) end), 3)
fresh:remove(deleted, true)
check("force remove", sync(function(cb) fresh:flush(cb) end), true)
check("row gone", raw("select count(*) from pet"), "2")
