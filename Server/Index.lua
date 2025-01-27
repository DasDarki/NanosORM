Package.Require("model.lua")
Package.Require("manager.lua")

local User = DefineModel("Users", {
    ID = Col(DataTypes.UUID):PrimaryKey():Default(),
    Username = DataTypes.STRING,
    Password = DataTypes.STRING,
    Email = DataTypes.STRING,
    Posts = Inverse(OneToMany("Posts"))
})

local Post = DefineModel("Posts", {
    ID = Col(DataTypes.UUID):PrimaryKey():Default(),
    Title = DataTypes.STRING,
    Content = DataTypes.STRING,
    Author = OneToMany(User)
})

DB.FinalizeModels()

print(NanosTable.Dump(DB._MODELS))
