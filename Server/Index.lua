Package.Require("datatypes.lua")
Package.Require("model.lua")
Package.Require("migrator.lua")

local Manager = Package.Require("manager.lua")

Manager.EnableDebug()
Manager.Initialize("db=database_filename.db timeout=2", DatabaseEngine["SQLite"])

local User = Manager.DefineModel("users", function (model) 
    model:Field("username", DataTypes.STRING):Unique():Default("")
    model:Field("email", DataTypes.STRING):Unique():Default("")
    model:Field("password", DataTypes.STRING)
end)

local Character = Manager.DefineModel("characters", function (model)
    model:Field("first_name", DataTypes.STRING):Default("")
    model:Field("last_name", DataTypes.STRING):Default("")
    
    model:Reference("user", User):OnDelete("CASCADE")
end)

Manager.AutoMigrate()


local user = User.Create()
user.username = "test"
user.email = "test@test.de"
user.password = "123"

user:Save()

local character = Character.Create()
character.first_name = "John"
character.last_name = "Doe"
character.user = user

character:Save()

