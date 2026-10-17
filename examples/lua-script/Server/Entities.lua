local ORM = NanosORM

local Entities = {}

Entities.Position = ORM.embeddable("Position")
    :column("x", "number")
    :column("y", "number")
    :column("z", "number")
    :build()

Entities.Resident = ORM.entity("Resident"):extends(ORM.Model)
    :column("id", "integer"):id()
    :column("name", "string"):length(32):unique()
    :column("wallet", "Money"):currency("EUR")
    :oneToMany("houses", "House", "owner"):orderBy("address")
    :oneToMany("vehicles", "Vehicle", "owner"):cascade("persist")
    :build()

Entities.House = ORM.entity("House")
    :column("id", "integer"):id()
    :column("address", "string"):length(64):unique()
    :column("price", "Money"):currency("EUR")
    :column("locked", "boolean")
    :embedded("door", Entities.Position)
    :manyToOne("owner", "Resident"):onDelete("SET NULL"):fetch("eager")
    :oneToMany("furniture", "Furniture", "house"):cascade("persist, remove"):orphanRemoval()
    :index({ "locked" })
    :build()

Entities.Furniture = ORM.entity("Furniture")
    :column("id", "integer"):id()
    :column("label", "string")
    :manyToOne("house", "House"):onDelete("CASCADE")
    :build()

Entities.Vehicle = ORM.entity("Vehicle")
    :inheritance("single", "kind")
    :abstract()
    :column("id", "integer"):id()
    :column("plate", "string"):length(8):unique()
    :manyToOne("owner", "Resident"):onDelete("CASCADE")
    :build()

Entities.Car = ORM.entity("Car"):extends(Entities.Vehicle)
    :column("seats", "integer")
    :build()

Entities.Bike = ORM.entity("Bike"):extends(Entities.Vehicle):discriminatorValue("motorbike")
    :column("helmet", "boolean")
    :build()

return Entities
