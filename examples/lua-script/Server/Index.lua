local ORM = NanosORM
local Expr, Agg, Money = ORM.Expr, ORM.Agg, ORM.Money
ORM.Currency.setDefault(ORM.Currency.of("EUR"))

local Entities = Package.Require("Entities.lua")
local Resident, House, Furniture, Car, Bike, Vehicle = Entities.Resident, Entities.House, Entities.Furniture, Entities.Car, Entities.Bike, Entities.Vehicle

local function log(message)
    Console.Log("%s", "[lua-demo] " .. tostring(message))
end

local settings = Server.GetCustomSettings()
local engine = settings.lua_demo_engine == "postgresql" and DatabaseEngine.PostgreSQL or DatabaseEngine.SQLite
local em = ORM.connect(engine, settings.lua_demo_connection or "db=lua-demo.db")

em:on("postPersist", function(house)
    log("event: house " .. house.address .. " persisted")
end, House)

local function fail(step, err)
    log("FAILED at " .. step .. ": " .. tostring(err))
end

local function seed(done)
    em:getRepository(Resident):count(nil, function(count, err)
        if count == nil then return fail("count residents", err) end
        if count > 0 then return done() end

        local carl = Resident.new({ name = "Carl", wallet = Money.of(250000) })
        local dana = Resident.new({ name = "Dana", wallet = Money.of(90000) })
        em:persist(carl)
        em:persist(dana)

        for index, address in ipairs({ "Grove Street 1", "Grove Street 2", "Vinewood Hills 7" }) do
            local house = House.new({ address = address, price = Money.of(50000 * index), locked = true })
            house.door.x = index * 100
            house.door.y = 20
            house.door.z = 0
            house.furniture = { Furniture.new({ label = "Sofa" }), Furniture.new({ label = "Bed" }) }
            em:persist(house)
        end

        carl.vehicles = { Car.new({ plate = "GROVE1", seats = 4 }), Bike.new({ plate = "BMX99", helmet = true }) }
        for _, vehicle in ipairs(carl.vehicles) do
            vehicle.owner = carl
        end

        em:flush(function(ok, flushErr)
            if not ok then return fail("seed flush", flushErr) end
            log("seeded residents, houses and vehicles")
            done()
        end)
    end)
end

local function buyHouse(buyer, address, done)
    em:transactional(function(tx, finish)
        tx:getRepository(House):findOneBy({ address = address }, function(house, err)
            if house == nil then return finish("no house at " .. address .. " " .. tostring(err)) end
            if house.owner ~= nil then return finish(address .. " is already owned by " .. house.owner.name) end
            if buyer.wallet:compareTo(house.price) < 0 then return finish(buyer.name .. " cannot afford " .. address) end

            buyer.wallet = buyer.wallet:minus(house.price)
            house.owner = buyer
            house.locked = false
            finish(house)
        end)
    end, function(ok, err, house)
        done(ok, ok and house or err)
    end)
end

local function renovate(houseAddress, done)
    em:beginTransaction(function(transaction, err)
        if transaction == nil then return done(false, err) end

        em:getRepository(House):query({ address = houseAddress }, { with = { "furniture" } }, function(houses)
            local house = houses[1]
            local sofa
            for _, item in ipairs(house.furniture) do
                if item.label == "Sofa" then sofa = item end
            end

            if sofa ~= nil then
                house.furniture:remove(sofa)
            end

            house.furniture:add(Furniture.new({ label = "Gaming Chair" }))
            house.door.z = 1
            if houseAddress == "Vinewood Hills 7" then
                transaction:rollback(function() done(false, "renovation of " .. houseAddress .. " cancelled") end)
                return
            end

            transaction:commit(done)
        end)
    end)
end

local function report()
    em:getRepository(House):createQueryBuilder()
        :where({ locked = false })
        :orWhere({ price = Expr.lt(Money.of(60000)) })
        :orderBy("address")
        :getResult(function(houses, err)
            if houses == nil then return fail("query builder", err) end
            for _, house in ipairs(houses) do
                log(string.format("%s: %s, owner %s, door at %.0f/%.0f/%.0f", house.address, house.price:format(), house.owner and house.owner.name or "-", house.door.x, house.door.y, house.door.z))
            end
        end)

    em:getRepository(Furniture):aggregate({
        select = { house = "house.address", pieces = Agg.count() },
        orderBy = { "house" }
    }, function(rows, err)
        if rows == nil then return fail("aggregate", err) end
        for _, row in ipairs(rows) do
            log("furniture in " .. row.house .. ": " .. row.pieces)
        end
    end)

    em:getRepository(Vehicle):findAll(function(vehicles, err)
        if vehicles == nil then return fail("vehicles", err) end
        for _, vehicle in ipairs(vehicles) do
            log("vehicle " .. vehicle.plate .. " is a " .. getmetatable(vehicle).__name .. " of " .. vehicle.owner.name)
        end
    end)

    em:nativeQuery("SELECT name, wallet FROM resident WHERE wallet > ? ORDER BY name", { Money.of(1000) }, function(rows, err)
        if rows == nil then return fail("native query", err) end
        for _, row in ipairs(rows) do
            log("native: " .. row.name .. " has " .. tostring(row.wallet))
        end
    end)
end

Console.RegisterCommand("lua_demo_report", report, "prints the state of the lua demo")

em:autoMigrate(function(ok, err, warnings)
    if not ok then return fail("autoMigrate", err) end
    for _, warning in ipairs(warnings or {}) do log("migration warning: " .. warning) end

    seed(function()
        em:getRepository(Resident):findBy({ name = Expr.isIn({ "Carl", "Dana" }) }, function(residents)
            local byName = {}
            for _, resident in ipairs(residents) do byName[resident.name] = resident end

            buyHouse(byName.Carl, "Grove Street 1", function(ok1, result1)
                log("Carl buys Grove Street 1: " .. tostring(ok1) .. " " .. (ok1 and result1.address or tostring(result1)))
                buyHouse(byName.Dana, "Grove Street 1", function(ok2, result2)
                    log("Dana buys Grove Street 1: " .. tostring(ok2) .. " " .. tostring(ok2 and result2.address or result2))
                    buyHouse(byName.Dana, "Vinewood Hills 7", function(ok3, result3)
                        log("Dana buys Vinewood Hills 7: " .. tostring(ok3) .. " " .. tostring(ok3 and result3.address or result3))
                        renovate("Grove Street 1", function(ok4, err4)
                            log("renovate Grove Street 1: " .. tostring(ok4) .. " " .. tostring(err4))
                            renovate("Vinewood Hills 7", function(ok5, err5)
                                log("renovate Vinewood Hills 7: " .. tostring(ok5) .. " " .. tostring(err5))
                                report()
                                log("scenario finished")
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end)
end)
