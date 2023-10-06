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

Manager.AutoMigrate()

local user = User.Find(1)
print(user.username)

user.password = "another"
user:Save()