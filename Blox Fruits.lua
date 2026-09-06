-- PuckAFK Blox Fruits v1.6.8 | Real dodge displacement + item-NPC/gear removed
local __PUCK_SOURCE = [========[
-- PuckAFK Blox Fruits v1.4.8 | Primary baseline: newer place 2753915549 Blox Fruits.rbxl, supplied 2026-09-06.
-- v1.5.6 keeps the proven v1.5.5 combat/gear logic unchanged and reorganizes the UI
-- into fewer tabs with collapsible advanced sections and clearer recommended paths.
-- Native combat and quest APIs; never guesses combat remote payloads.
-- v1.4.1 revalidated against the fuller supplied place dump (5,620 decompiled client source blocks).
-- Exact current WeaponToolClient / CombatController / CombatUtil paths and M1 hit-part rules are used below.
-- PuckUI v3.8.0 is bundled below with service-input connection cleanup. See accompanying inspection report.
-- v1.6.7 removes the unreliable item-NPC / gear automation completely. Core farming, combat, movement, fruits, weapons, styles and Haki remain.
-- v1.6.8 makes Auto Dodge physically displace the character with a short dedicated lateral burst instead of only retargeting the normal combat follow.
local VERSION = "1.6.8"
local Env = _G
if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)
    if ok and type(result) == "table" then Env = result end
end
local KEY = "__PUCKAFK_BLOXFRUITS_RUNTIME"
if type(Env[KEY]) == "table" and type(Env[KEY].Shutdown) == "function" then
    Env[KEY]:Shutdown("Re-executed")
end
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Tags = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local StarterGui = game:GetService("StarterGui")
local Player

-- Blox Fruits uses a dedicated Roblox place for each main sea.  This is the
-- fastest and most reliable world signal available to the client and avoids
-- blocking Auto Level on ReplicatedStorage.Util.Realm:getCurrentSeaAsync().
local SEA_BY_PLACE = {
    [2753915549] = "Sea1",
    [4442272183] = "Sea2",
    [7449423635] = "Sea3",
}

local Runtime = {
    Running = true, Ready = false, State = "LOADING", Detail = "Waiting for game",
    StateSince = os.clock(), Started = os.clock(), Connections = {}, Workers = {},
    Target = nil, Quest = nil, Owner = nil, Generation = 0, Sea = SEA_BY_PLACE[game.PlaceId],
    SeaSource = SEA_BY_PLACE[game.PlaceId] and "PlaceId" or "Pending",
    LastError = "None", LastRecovery = "None", Logs = {}, Window = nil,
    ActiveQuest = nil, ActiveQuestKnown = false, QuestSyncAt = 0,
    ProgressAt = os.clock(), PauseUntil = 0, CombatAt = 0, FarmSeconds = 0,
    Counters = {Targets = 0, Quests = 0, Recoveries = 0, FruitRolls = 0, FruitsCollected = 0, Purchases = 0, ServerHops = 0}, Modules = {},
    ServerStatus = "Idle", GachaStatus = "Idle", FruitShopStatus = "Not checked", FruitPickupStatus = "Idle", PurchaseStatus = "Idle",
    CombatHitPart = "None", CombatPath = "Idle", M1Status = "Waiting", CameraStatus = "Idle", DodgeStatus = "Watching",
}
Env[KEY] = Runtime
local Config = {
    AutoLevel = false, AutoBoss = false, AutoEnemy = false, Boss = "Auto available",
    Enemy = "Select enemy", BossQuest = true, RepeatBoss = true,
    WeaponMode = "Auto", Weapon = "Auto", Position = "Above", Distance = 3,
    Height = 0, Side = 0, AboveLookDown = true, AboveLookDownAngle = 45,
    OrbitRadius = 4, OrbitSpeed = 35,
    Movement = "Smooth", Speed = 100, NoCollision = true,
    AttackInterval = 0.22, CameraAim = true, AutoAura = false, AutoDodge = true,
    AutoSkills = true, SkillZ = true, SkillX = true, SkillC = true, SkillV = true, SkillF = false,
    SkillAim = true, SkillHold = 0.12, SkillMaxRange = 55,
    AvoidContested = true, ContestedSeconds = 5,
    Mastery = false, MasteryWeapon = "Select weapon", FinishPercent = 25,
    AutoStats = false, StatMelee = false, StatDefense = false, StatSword = false,
    StatGun = false, StatFruit = false, StatBatch = 1, StatDistribution = "Lowest stat",
    AntiAFK = true,
    AutoSmallServer = false, MaxOtherPlayers = 9, ExemptFriend = "",
    HideOwnNameplate = false, HidePlayerList = false,
    AutoRandomFruit = false, FruitMoneyReserve = 0,
    AutoCollectSpawnedFruits = true, AutoStoreSpawnedFruits = true,
    FruitDealer = "Normal", StockFruit = "Select fruit", DragonType = "East", AutoBuyStockFruit = false,
    ShopWeapon = "Katana", AutoBuyWeapon = false,
    FightingStyle = "Dark Step", AutoBuyStyle = false,
    HakiAbility = "Aura", AutoBuyHaki = false,
    Debug = false,
}
Runtime.Config = Config
local Movement, Combat, QuestService, EnemyService, UI, PrivacyService, ServerService, FruitGachaService, FruitShopService, FruitPickupService, CombatSkillService, PurchaseService, DodgeService
local function log(kind, message)
    message = tostring(message)
    if kind == "Error" then Runtime.LastError = message end
    table.insert(Runtime.Logs, {Time = math.floor(os.clock() - Runtime.Started), Kind = kind, Message = message})
    if #Runtime.Logs > 80 then table.remove(Runtime.Logs, 1) end
    if Config.Debug then warn("[PuckAFK/BloxFruits] " .. kind .. ": " .. message) end
end
local function state(name, detail)
    if Runtime.State ~= name then Runtime.StateSince = os.clock() end
    Runtime.State, Runtime.Detail = name, detail or name
end
local function connect(signal, callback, list)
    local c = signal:Connect(callback)
    table.insert(list or Runtime.Connections, c)
    return c
end
local function disconnectAll(list)
    for _, c in ipairs(list) do c:Disconnect() end
    table.clear(list)
end
local function worker(name, callback)
    if Runtime.Workers[name] or not Runtime.Running then return false end
    local record = {Started = os.clock()}
    Runtime.Workers[name] = record
    record.Thread = task.defer(function()
        local ok, err = xpcall(callback, debug.traceback)
        if Runtime.Workers[name] == record then Runtime.Workers[name] = nil end
        if not ok and Runtime.Running then log("Error", name .. ": " .. tostring(err)) end
    end)
    return true
end
local function path(root, ...)
    for _, name in ipairs({...}) do
        if not root then return nil end
        root = root:FindFirstChild(name)
    end
    return root
end
local function value(root, name, fallback)
    local node = root and root:FindFirstChild(name)
    if node and node:IsA("ValueBase") then return node.Value end
    return fallback
end
local function char()
    local c = Player and Player.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if c and c.Parent and h and h.Health > 0 and r and r:IsA("BasePart") then return c, h, r end
end
local ENEMY_ALIASES = {
    ["Magma Admiral"] = "Magma General",
    ["Wysper"] = "Sky Warlord",
    ["Thunder God"] = "Lightning God",
}
local function normalize(name)
    local clean = tostring(name or ""):gsub("%s*%b[]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return ENEMY_ALIASES[clean] or clean
end
local function pos(instance)
    if not instance then return nil end
    if instance:IsA("BasePart") then return instance.Position end
    if instance:IsA("Vector3Value") then return instance.Value end
    if instance:IsA("Model") then
        local r = instance:FindFirstChild("HumanoidRootPart") or instance.PrimaryPart
        if r then return r.Position end
    end
end
local function vec(array) return Vector3.new(array[1], array[2], array[3]) end
local function notify(message)
    if UI then UI:Notify({Title = "PuckAFK · Blox Fruits", Content = message, Duration = 4}) end
end
local function selectedOwner()
    if PurchaseService and PurchaseService:HasTravelWork() then return "Shop" end
    if Config.AutoBoss then return "Boss" end
    if Config.AutoEnemy then return "Enemy" end
    if Config.AutoLevel then return "Level" end
    if Config.AutoCollectSpawnedFruits and FruitPickupService and FruitPickupService:HasWork() then return "Fruit" end
end
local function release(reason)
    Runtime.Generation = Runtime.Generation + 1
    if Movement then Movement:Cancel(reason) end
    if Combat then Combat:Stop() end
    if DodgeService then DodgeService:Clear("Watching") end
    Runtime.Target, Runtime.Quest = nil, nil
    Runtime.ProgressAt = os.clock()
end
function Runtime:Shutdown(reason)
    if not self.Running then return end
    self.Running, self.Ready = false, false
    release(reason or "Unloaded")
    disconnectAll(self.Connections)
    if PrivacyService then PrivacyService:Restore() end
    if EnemyService then EnemyService:Destroy() end
    if FruitPickupService then FruitPickupService:Destroy() end
    if DodgeService then DodgeService:Destroy() end
    for _, record in pairs(self.Workers) do
        if record.Thread and coroutine.status(record.Thread) ~= "dead" then pcall(task.cancel, record.Thread) end
    end
    table.clear(self.Workers)
    if self.Loop and self.Loop ~= coroutine.running() then pcall(task.cancel, self.Loop) end
    if self.Window then self.Window:Destroy() end
    if Env[KEY] == self then Env[KEY] = nil end
end
local deadline = os.clock() + 60
while Runtime.Running and (not game:IsLoaded() or not Players.LocalPlayer) and os.clock() < deadline do task.wait(0.25) end
if not Runtime.Running then return end
Player = Players.LocalPlayer
if not Player or not game:IsLoaded() then Runtime:Shutdown("Game load timed out"); warn("PuckAFK: Game did not load within 60 seconds. Execute again after joining."); return end
if Runtime.Sea then log("World", Runtime.Sea .. " via PlaceId " .. tostring(game.PlaceId)) end
local GameData = {["npcNames"]={["Cupid_ValentineDailyQuests"]="Cupid Valentine Quest Giver",["DesertMerchant"]="Desert Merchant",["BuggyQuest1"]="Pirate Adventurer",["BanditQuest1"]="Bandit Quest Giver",["JungleQuest"]="Adventurer",["DesertQuest"]="Desert Adventurer",["SnowQuest"]="Villager",["MarineQuest"]="Marine Leader",["SkyQuest"]="Sky Adventurer",["MarineQuest2"]="Marine",["ColosseumQuest"]="Colosseum Quest Giver",["PrisonerQuest"]="Jail Keeper",["ImpelQuest"]="Head Jailer",["MagmaQuest"]="The Mayor",["FishmanQuest"]="King Neptune",["SkyExp1Quest"]="Mole",["SkyExp2Quest"]="Sky Quest Giver 2",["AngelGuard"]="Angel Guard",["FountainQuest"]="Freezeburg Quest Giver",["Bartilo"]="Bartilo",["Citizen"]="Citizen",["HornedMan"]="Horned Man",["ArenaTrainer"]="Arena Trainer",["StartValentinesDelivery"]="Valentines Delivery",["Area1Quest"]="Area 1 Quest Giver",["Area2Quest"]="Area 2 Quest Giver",["MarineQuest3"]="Marine Quest Giver",["ZombieQuest"]="Graveyard Quest Giver",["SnowMountainQuest"]="Snow Quest Giver",["IceSideQuest"]="Ice Quest Giver",["FireSideQuest"]="Fire Quest Giver",["ShipQuest1"]="Rear Crew Quest Giver",["ShipQuest2"]="Front Crew Quest Giver",["FrostQuest"]="Frost Quest Giver",["ForgottenQuest"]="Forgotten Quest Giver",["PiratePortQuest"]="Pirate Port Quest Giver",["DragonCrewQuest"]="Dragon Crew Quest Giver",["VenomCrewQuest"]="Hydra Town Quest Giver",["MarineTreeIsland"]="Marine Tree Quest Giver",["DeepForestIsland"]="Deep Forest Quest Giver",["DeepForestIsland2"]="Deep Forest Area 2 Quest Giver",["DeepForestIsland3"]="Turtle Adventure Quest Giver",["HauntedQuest1"]="Haunted Castle Quest Giver 1",["HauntedQuest2"]="Haunted Castle Quest Giver 2",["NutsIslandQuest"]="Peanut Quest Giver",["IceCreamIslandQuest"]="Ice Cream Quest Giver",["CakeQuest1"]="Cake Quest Giver 1",["CakeQuest2"]="Cake Quest Giver 2",["ChocQuest1"]="Chocolate Quest Giver 1",["ChocQuest2"]="Chocolate Quest Giver 2",["CandyQuest1"]="Candy Cane Quest Giver",["TikiQuest1"]="Tiki Quest Giver 1",["TikiQuest2"]="Tiki Quest Giver 2",["TikiQuest3"]="Tiki Quest Giver 3",["SubmergedQuest1"]="Submerged Quest Giver 1",["SubmergedQuest2"]="Submerged Quest Giver 2",["SubmergedQuest3"]="Submerged Quest Giver 3",["LeviathanGate"]="Frozen Watcher",["FishTournamentNpc"]="Tournament Master",["RedRecruiter"]="Red Army Recruiter",["SecretSanta"]="Secret Santa",["ColosseumEmperor"]="Colosseum Emperor"},["sea1NPCPositions"]={["DesertMerchant"]={{861.7816,5.2202,4452.9434}},["BuggyQuest1"]={{-1151.5861,16.6153,3863.125}},["BanditQuest1"]={{1051.7979,14.5131,1557.7426}},["JungleQuest"]={{-1679.7632,48.74,175.64}},["DesertQuest"]={{931.378,4.684,4198.2129}},["SnowQuest"]={{1400.5638,77.391,-1311.285}},["MarineQuest"]={{-2655.2842,30.5667,2113.7244}},["SkyQuest"]={{-4750.1802,966.0667,-748.2415}},["MarineQuest2"]={{-4699.3311,4.741,4227.6392}},["ColosseumQuest"]={{-1342.2555,11.1514,-2928.5808}},["PrisonerQuest"]={{5208.3394,18.872,736.5863}},["ImpelQuest"]={{5320.666,18.8856,856.2814}},["MagmaQuest"]={{-5308.8672,17.035,8482.6982}},["FishmanQuest"]={{61406.1953,24.5187,1626.8164}},["SkyExp1Quest"]={{-4882.894,926.1775,-1031.0548},{-5949.0674,5467.9399,2086.5151}},["SkyExp2Quest"]={{-7033.1006,5590.5742,1353.1069}},["AngelGuard"]={{-4820.915,936.7914,-1151.9858}},["FountainQuest"]={{5263.4878,74.908,4087.6157}},["ColosseumEmperor"]={{-1846.5775,90.6153,-3333.6003}}},["sea1Spawns"]={["Galley Pirate"]={{5452.8906,78.7009,4112.5771},{5327.6138,76.2443,4014.5054},{5670.6528,79.5117,4074.4634},{5840.0259,76.8321,3975.5635},{5708.2217,80.9137,3928.1187},{5430.4199,77.9911,3953.5669}},["Mob Boss"]={{-2880.7161,6.6902,5430.853}},["Monkey"]={{-1525.5555,27.247,163.9578},{-1637.5546,29.9774,19.6401},{-1866.3134,29.9336,21.5892},{-1450.6416,28.9805,306.1212},{-1610.2397,29.1658,399.6645},{-1758.6613,30.8861,-31.8154},{-1299.4272,17.6544,81.422}},["Trainee"]={{-2674.5237,32.1167,2186.9727},{-2728.6411,32.9167,1966.2179},{-2741.041,32.9167,1900.0179},{-2748.0374,30.3167,2152.7031},{-2788.251,30.687,2281.481},{-2667.4412,32.9167,1900.0179},{-2710.5703,30.687,2242.8457}},["Fishman Warrior"]={{60930.9219,23.7948,1393.0935},{60892.2578,23.8054,1500.4952},{60715.9922,25.2567,1284.8903},{60788.3633,23.804,1484.5264},{60736.8125,23.7955,1396.3376},{60859.6602,23.7886,1328.1914},{60626.4102,25.2498,1142.8281}},["Chief Petty Officer"]={{-5002.21,11.0317,4004.7393},{-4763.6768,13.3913,4288.8428},{-4938.3613,11.0317,3995.8711},{-4780.5425,13.8793,4419.9072},{-4836.437,16.3297,4465.7817},{-4650.5903,11.0317,4562.0977},{-4674.6328,11.0317,4483.3257},{-4828.5825,13.1261,4196.7866}},["Royal Squad"]={{-6868.939,5554.8901,1319.9546},{-6706.8706,5551.4136,1155.4302},{-6804.6875,5550.374,1083.5612},{-6690.0396,5551.4136,1318.3054},{-6920.7334,5551.4136,1191.9246}},["Royal Soldier"]={{-7137.4277,5541.0503,892.9871},{-6938.3843,5541.0503,963.7812},{-7138.4819,5541.0503,1050.7743},{-7175.8354,5541.0503,947.144},{-6932.0879,5541.0503,842.4445}},["Gorilla"]={{-1387.3282,14.4667,-577.8},{-1401.088,26.4667,-463.9571},{-1198.4189,17.3038,-689.8491},{-1266.5652,14.4667,-462.0237}},["Vice Admiral"]={{-5010.8198,15.0616,4383.7275}},["The Gorilla King"]={{-1193.9066,10.7215,-549.8473}},["Military Spy"]={{-5952.5493,76.9223,8742.4033},{-5714.9185,76.592,8834.8584},{-5808.9834,77.3133,8791.2041},{-5889.9629,76.614,8723.0107}},["Military Soldier"]={{-5623.7983,17.0068,8314.0566},{-5266.3911,17.1309,8554.1934},{-5694.48,17.0068,8329.207},{-5337.0879,17.1308,8629.3164},{-5418.478,18.009,8421.084}},["Magma General"]={{-5625.71,55.4438,8623.0117}},["Fishman Commando"]={{61992.6406,24.5499,1205.738},{61887.75,24.5489,1232.447},{62013.0312,24.5534,1329.9451},{61808.0977,24.5535,1328.5818},{61994.5547,24.5499,1425.449},{61872.875,24.5667,1464.1794}},["Saber Expert"]={{-1527.2043,34.092,-33.1601}},["Dark Master"]={{-5411.2544,504.9326,-372.7786},{-5283.166,505.0639,-221.0142},{-5269.0063,504.9826,-461.1162},{-5206.772,504.7442,-348.4639}},["Galley Captain"]={{5409.4785,77.6743,4686.9922},{5782.2031,79.3242,4868.8643},{5385.4746,78.7069,4851.1211},{5594.9336,78.7114,4751.8667},{5899.5762,76.5876,4809.0225},{5544.0356,76.87,4899.0986},{5773.7266,77.6645,4703.1021},{5685.416,77.6837,4742.5859}},["Gladiator"]={{-1118.9137,11.6226,-3014.1589},{-1161.9137,11.6226,-3097.1589},{-1238.9137,11.6226,-3241.1589},{-1212.6302,11.6226,-3378.6699},{-1144.4741,11.6226,-3337.3591}},["Cyborg"]={{6252.3916,9.3188,4941.3887}},["Dangerous Prisoner"]={{5329.3354,49.4213,819.4515},{5295.2734,9.1438,1104.7812},{5058.2627,9.1438,900.9187},{5271.3623,16.372,799.6079},{5393.915,16.372,795.2637},{5393.915,16.372,673.5815},{5122.9136,9.1438,969.8962},{5456.3853,9.1438,955.9614},{5188.8506,9.1438,1058.125},{5272.9414,16.372,673.5815}},["Prisoner"]={{5457.6909,7.1336,507.4754},{5192.9854,7.1336,414.3049},{5370.8384,7.1336,459.1865},{5278.5913,7.1336,391.5569},{5057.8096,7.1336,567.154}},["Warden"]={{5623.1655,1.3567,733.8089}},["Lightning God"]={{-7125.4146,5596.063,111.5187}},["God's Guard"]={{-4227.251,1087.9636,-567.6089},{-4403.3276,1088.2157,-498.13},{-4364.7642,1090.1718,-383.4792},{-4234.5562,1089.3344,-267.3759},{-4082.8511,1087.2667,-414.1362},{-4130.8027,1090.3033,-291.2061}},["Sky Bandit"]={{-4973.7432,280.7215,-1119.4304},{-5221.6445,280.7215,-1068.6399},{-5014.0342,280.7215,-972.0793},{-5157.0664,280.7215,-916.718}},["Toga Warrior"]={{-1819.4803,9.219,-2736.5649},{-1829.7235,9.0293,-2661.5325},{-1620.103,12.4893,-2672.2935},{-1973.1317,9.0293,-2744.9353},{-1533.1406,12.4893,-2781.2935},{-1694.7518,9.219,-2633.2627}},["Fishman Lord"]={{61352.9023,67.167,1029.111}},["Yeti"]={{1181.6616,104.033,-1616.9319}},["Snowman"]={{1121.5498,98.1666,-1669.0242},{1149.4885,98.2227,-1540.4639},{1272.3619,98.3292,-1647.2545},{1246.7688,98.3292,-1555.6941}},["Snow Bandit"]={{1519.4727,77.9602,-1510.9379},{1501.9574,77.9602,-1402.3721},{1431.7507,77.9602,-1444.8923},{1364.1162,77.9602,-1429.6514},{1260.2578,77.9602,-1387.6104}},["Shanda"]={{-6026.8364,5469.5527,1851.0494},{-5956.5015,5470.0903,1750.6016},{-6040.2041,5468.0132,1734.2095},{-5878.7881,5470.4385,1864.2034},{-5890.4121,5468.9048,1956.187}},["Sky Warlord"]={{-6271.5586,5472.7764,1887.7705}},["Ice Admiral"]={{1212.3831,20.398,-1429.639}},["Desert Bandit"]={{860.5411,7.565,4539.7974},{999.8505,7.565,4490.3311},{902.8602,7.565,4461.4214},{931.705,7.565,4564.5332}},["Desert Officer"]={{1608.3976,14.148,4112.2891},{1615.4906,14.248,4187.3862},{1543.9927,14.115,4240.9756},{1523.7845,15.285,4095.4282}},["Pirate"]={{-1313.745,18.8687,3964.1853},{-1122.7827,19.9353,3965.8818},{-1285.0845,18.0345,3886.9673},{-1176.7651,19.742,4027.27},{-980.9808,30.4456,3966.8323},{-963.942,27.6461,4043.7151}},["Brute"]={{-1350.1282,28.1044,4285.1089},{-942.3545,29.7292,4387.2441},{-1312.8051,28.1044,4402.8594},{-1085.9435,28.1044,4342.6719},{-1436.7837,28.1044,4357.1997},{-1094.9333,28.1044,4442.9072}},["Chef"]={{-1120.4521,54.707,4121.1572}},["Bandit"]={{1310.6608,13.4736,1593.0652},{922.1547,13.1856,1528.032},{937.9623,13.1856,1588.8494},{1210.0192,13.1856,1673.5321},{1203.5729,13.1856,1563.3494},{1148.6528,13.1856,1669.2899},{1261.4645,13.1856,1619.0662},{1280.7506,13.4736,1528.9128},{1013.3794,13.1856,1565.4988},{1114.2612,13.1856,1590.1833}}}}

-- Exact quest database extracted from the supplied 2026-09-05 Blox Fruits dump.
-- This removes Auto Level's dependency on requiring ReplicatedStorage.Quests at runtime.
local BUNDLED_QUESTS = {
	BanditQuest1 = {
		{
			LevelReq = 0,
			Name = "Bandits",
			Task = {
				Bandit = 5
			},
			Reward = {
				Beli = 350,
				Exp = 300
			}
		}
	},
	MarineQuest = {
		{
			LevelReq = 0,
			Name = "Trainees",
			Task = {
				Trainee = 5
			},
			Reward = {
				Beli = 350,
				Exp = 300
			}
		}
	},
	JungleQuest = {
		{
			LevelReq = 10,
			Name = "Monkeys",
			Task = {
				Monkey = 6
			},
			Reward = {
				Beli = 800,
				Exp = 2300
			}
		},
		{
			LevelReq = 15,
			Name = "Gorillas",
			Task = {
				Gorilla = 8
			},
			Reward = {
				Beli = 1200,
				Exp = 4500
			}
		},
		{
			LevelReq = 20,
			Name = "Gorilla King",
			Task = {
				["The Gorilla King"] = 1
			},
			Reward = {
				Beli = 2000,
				Exp = 9500
			}
		}
	},
	BuggyQuest1 = {
		{
			LevelReq = 30,
			Name = "Pirates",
			Task = {
				Pirate = 8
			},
			Reward = {
				Beli = 3000,
				Exp = 13000
			}
		},
		{
			LevelReq = 40,
			Name = "Brute",
			Task = {
				Brute = 8
			},
			Reward = {
				Beli = 3500,
				Exp = 22000
			}
		},
		{
			LevelReq = 55,
			Name = "Chef",
			Task = {
				Chef = 1
			},
			Reward = {
				Beli = 8000,
				Exp = 45000
			}
		}
	},
	DesertQuest = {
		{
			LevelReq = 60,
			Name = "Desert Bandit",
			Task = {
				["Desert Bandit"] = 8
			},
			Reward = {
				Beli = 4000,
				Exp = 45000
			}
		},
		{
			LevelReq = 75,
			Name = "Desert Officer",
			Task = {
				["Desert Officer"] = 6
			},
			Reward = {
				Beli = 4500,
				Exp = 65000
			}
		}
	},
	SnowQuest = {
		{
			LevelReq = 90,
			Name = "Snow Bandit",
			Task = {
				["Snow Bandit"] = 7
			},
			Reward = {
				Beli = 5000,
				Exp = 90000
			}
		},
		{
			LevelReq = 100,
			Name = "Snowman",
			Task = {
				Snowman = 8
			},
			Reward = {
				Beli = 5500,
				Exp = 150000
			}
		},
		{
			LevelReq = 105,
			Name = "Yeti",
			Task = {
				Yeti = 1
			},
			Reward = {
				Beli = 10000,
				Exp = 220000
			}
		}
	},
	MarineQuest2 = {
		{
			LevelReq = 120,
			Name = "Chief Petty Officer",
			Task = {
				["Chief Petty Officer"] = 8
			},
			Reward = {
				Beli = 6000,
				Exp = 225000
			}
		},
		{
			LevelReq = 130,
			Name = "Vice Admiral",
			Task = {
				["Vice Admiral"] = 1
			},
			Reward = {
				Beli = 15000,
				Exp = 415000
			}
		}
	},
	SkyQuest = {
		{
			LevelReq = 150,
			Name = "Sky Bandit",
			Task = {
				["Sky Bandit"] = 7
			},
			Reward = {
				Beli = 7000,
				Exp = 315000
			}
		},
		{
			LevelReq = 175,
			Name = "Dark Master",
			Task = {
				["Dark Master"] = 8
			},
			Reward = {
				Beli = 7500,
				Exp = 450000
			}
		}
	},
	PrisonerQuest = {
		{
			LevelReq = 190,
			Name = "Prisoner",
			Task = {
				Prisoner = 8
			},
			Reward = {
				Beli = 7000,
				Exp = 550000
			}
		},
		{
			LevelReq = 210,
			Name = "Dangerous Prisoner",
			Task = {
				["Dangerous Prisoner"] = 8
			},
			Reward = {
				Beli = 7500,
				Exp = 780000
			}
		}
	},
	ImpelQuest = {
		{
			LevelReq = 225,
			Name = "Ruthless Prisoner",
			Task = {
				["Ruthless Prisoner"] = 8
			},
			Reward = {
				Beli = 8000,
				Exp = 900000
			}
		},
		{
			LevelReq = 230,
			Name = "Warden",
			Task = {
				Warden = 1
			},
			Reward = {
				Beli = 10000,
				Exp = 1000000
			}
		}
	},
	ColosseumQuest = {
		{
			LevelReq = 250,
			Name = "Toga Warrior",
			Task = {
				["Toga Warrior"] = 7
			},
			Reward = {
				Beli = 7000,
				Exp = 1100000
			}
		},
		{
			LevelReq = 275,
			Name = "Gladiator",
			Task = {
				Gladiator = 8
			},
			Reward = {
				Beli = 7500,
				Exp = 1300000
			}
		}
	},
	MagmaQuest = {
		{
			LevelReq = 300,
			Name = "Mil. Soldier",
			Task = {
				["Military Soldier"] = 7
			},
			Reward = {
				Beli = 8250,
				Exp = 1700000
			}
		},
		{
			LevelReq = 325,
			Name = "Mil. Spy",
			Task = {
				["Military Spy"] = 8
			},
			Reward = {
				Beli = 8500,
				Exp = 2000000
			}
		},
		{
			LevelReq = 350,
			Name = "Magma Admiral",
			Task = {
				["Magma Admiral"] = 1
			},
			Reward = {
				Beli = 15000,
				Exp = 3000000
			}
		}
	},
	FishmanQuest = {
		{
			LevelReq = 375,
			Name = "Fishman Warrior",
			Task = {
				["Fishman Warrior"] = 8
			},
			Reward = {
				Beli = 8750,
				Exp = 3050000
			}
		},
		{
			LevelReq = 400,
			Name = "Fishman Commando",
			Task = {
				["Fishman Commando"] = 7
			},
			Reward = {
				Beli = 9000,
				Exp = 3350000
			}
		},
		{
			LevelReq = 425,
			Name = "Fishman Lord",
			Task = {
				["Fishman Lord"] = 1
			},
			Reward = {
				Beli = 15000,
				Exp = 4250000
			}
		}
	},
	SkyExp1Quest = {
		{
			LevelReq = 450,
			Name = "God\'s Guard",
			Task = {
				["God\'s Guard"] = 7
			},
			Reward = {
				Beli = 8750,
				Exp = 4250000
			}
		},
		{
			LevelReq = 475,
			Name = "Shanda",
			Task = {
				Shanda = 9
			},
			Reward = {
				Beli = 9000,
				Exp = 5000000
			}
		},
		{
			LevelReq = 500,
			Name = "Wysper",
			Task = {
				Wysper = 1
			},
			Reward = {
				Beli = 15000,
				Exp = 5700000
			}
		}
	},
	SkyExp2Quest = {
		{
			LevelReq = 525,
			Name = "Royal Squad",
			Task = {
				["Royal Squad"] = 8
			},
			Reward = {
				Beli = 9500,
				Exp = 5800000
			}
		},
		{
			LevelReq = 550,
			Name = "Royal Soldier",
			Task = {
				["Royal Soldier"] = 8
			},
			Reward = {
				Beli = 9750,
				Exp = 6300000
			}
		},
		{
			LevelReq = 575,
			Name = "Thunder God",
			Task = {
				["Thunder God"] = 1
			},
			Reward = {
				Beli = 20000,
				Exp = 8000000
			}
		}
	},
	FountainQuest = {
		{
			LevelReq = 625,
			Name = "Galley Pirate",
			Task = {
				["Galley Pirate"] = 8
			},
			Reward = {
				Beli = 10000,
				Exp = 7500000
			}
		},
		{
			LevelReq = 650,
			Name = "Galley Captain",
			Task = {
				["Galley Captain"] = 9
			},
			Reward = {
				Beli = 10000,
				Exp = 8500000
			}
		},
		{
			LevelReq = 675,
			Name = "Cyborg",
			Task = {
				Cyborg = 1
			},
			Reward = {
				Beli = 20000,
				Exp = 10000000
			}
		}
	},
	Area1Quest = {
		{
			LevelReq = 700,
			Name = "Raider",
			Task = {
				Raider = 8
			},
			Reward = {
				Beli = 10250,
				Exp = 8750000
			}
		},
		{
			LevelReq = 725,
			Name = "Mercenary",
			Task = {
				Mercenary = 8
			},
			Reward = {
				Beli = 10500,
				Exp = 9750000
			}
		},
		{
			LevelReq = 750,
			Name = "Diamond",
			Task = {
				Diamond = 1
			},
			Reward = {
				Beli = 25000,
				Exp = 12500000
			}
		}
	},
	Area2Quest = {
		{
			LevelReq = 775,
			Name = "Swan Pirate",
			Task = {
				["Swan Pirate"] = 8
			},
			Reward = {
				Beli = 10750,
				Exp = 11500000
			}
		},
		{
			LevelReq = 800,
			Name = "Factory Staff",
			Task = {
				["Factory Staff"] = 8
			},
			Reward = {
				Beli = 11000,
				Exp = 13000000
			}
		},
		{
			LevelReq = 850,
			Name = "Jeremy",
			Task = {
				Jeremy = 1
			},
			Reward = {
				Beli = 25000,
				Exp = 16000000
			}
		}
	},
	MarineQuest3 = {
		{
			LevelReq = 875,
			Name = "Marine Lieutenant",
			Task = {
				["Marine Lieutenant"] = 8
			},
			Reward = {
				Beli = 11250,
				Exp = 15000000
			}
		},
		{
			LevelReq = 900,
			Name = "Marine Captain",
			Task = {
				["Marine Captain"] = 9
			},
			Reward = {
				Beli = 11500,
				Exp = 16500000
			}
		},
		{
			LevelReq = 925,
			Name = "Orbitus",
			Task = {
				Orbitus = 1
			},
			Reward = {
				Beli = 25000,
				Exp = 19000000
			}
		}
	},
	ZombieQuest = {
		{
			LevelReq = 950,
			Name = "Zombie",
			Task = {
				Zombie = 8
			},
			Reward = {
				Beli = 11750,
				Exp = 19000000
			}
		},
		{
			LevelReq = 975,
			Name = "Vampire",
			Task = {
				Vampire = 8
			},
			Reward = {
				Beli = 12000,
				Exp = 20500000
			}
		}
	},
	SnowMountainQuest = {
		{
			LevelReq = 1000,
			Name = "Snow Trooper",
			Task = {
				["Snow Trooper"] = 8
			},
			Reward = {
				Beli = 12250,
				Exp = 22500000
			}
		},
		{
			LevelReq = 1050,
			Name = "Winter Warrior",
			Task = {
				["Winter Warrior"] = 9
			},
			Reward = {
				Beli = 12500,
				Exp = 24000000
			}
		}
	},
	IceSideQuest = {
		{
			LevelReq = 1100,
			Name = "Lab Subordinate",
			Task = {
				["Lab Subordinate"] = 8
			},
			Reward = {
				Beli = 12250,
				Exp = 25500000
			}
		},
		{
			LevelReq = 1125,
			Name = "Horned Warrior",
			Task = {
				["Horned Warrior"] = 9
			},
			Reward = {
				Beli = 12500,
				Exp = 27000000
			}
		},
		{
			LevelReq = 1150,
			Name = "Smoke Admiral",
			Task = {
				["Smoke Admiral"] = 1
			},
			Reward = {
				Beli = 20000,
				Exp = 32500000
			}
		}
	},
	FireSideQuest = {
		{
			LevelReq = 1175,
			Name = "Magma Ninja",
			Task = {
				["Magma Ninja"] = 8
			},
			Reward = {
				Beli = 12250,
				Exp = 29000000
			}
		},
		{
			LevelReq = 1200,
			Name = "Lava Pirate",
			Task = {
				["Lava Pirate"] = 8
			},
			Reward = {
				Beli = 12500,
				Exp = 31000000
			}
		}
	},
	ShipQuest1 = {
		{
			LevelReq = 1250,
			Name = "Ship Deckhand",
			Task = {
				["Ship Deckhand"] = 8
			},
			Reward = {
				Beli = 12250,
				Exp = 33000000
			}
		},
		{
			LevelReq = 1275,
			Name = "Ship Engineer",
			Task = {
				["Ship Engineer"] = 8
			},
			Reward = {
				Beli = 12500,
				Exp = 35500000
			}
		}
	},
	ShipQuest2 = {
		{
			LevelReq = 1300,
			Name = "Ship Steward",
			Task = {
				["Ship Steward"] = 8
			},
			Reward = {
				Beli = 12250,
				Exp = 37500000
			}
		},
		{
			LevelReq = 1325,
			Name = "Ship Officer",
			Task = {
				["Ship Officer"] = 8
			},
			Reward = {
				Beli = 12500,
				Exp = 39500000
			}
		}
	},
	FrostQuest = {
		{
			LevelReq = 1350,
			Name = "Arctic Warrior",
			Task = {
				["Arctic Warrior"] = 8
			},
			Reward = {
				Beli = 12250,
				Exp = 41000000
			}
		},
		{
			LevelReq = 1375,
			Name = "Snow Lurker",
			Task = {
				["Snow Lurker"] = 8
			},
			Reward = {
				Beli = 12500,
				Exp = 43000000
			}
		},
		{
			LevelReq = 1400,
			Name = "Ice Admiral",
			Task = {
				["Awakened Ice Admiral"] = 1
			},
			Reward = {
				Beli = 20000,
				Exp = 45000000
			}
		}
	},
	ForgottenQuest = {
		{
			LevelReq = 1425,
			Name = "Sea Soldier",
			Task = {
				["Sea Soldier"] = 8
			},
			Reward = {
				Beli = 12250,
				Exp = 47000000
			}
		},
		{
			LevelReq = 1450,
			Name = "Water Fighter",
			Task = {
				["Water Fighter"] = 8
			},
			Reward = {
				Beli = 12500,
				Exp = 49000000
			}
		},
		{
			LevelReq = 1475,
			Name = "Tide Keeper",
			Task = {
				["Tide Keeper"] = 1
			},
			Reward = {
				Beli = 12500,
				Exp = 51000000
			}
		}
	},
	PiratePortQuest = {
		{
			LevelReq = 1500,
			Name = "Pirate Millionaire",
			Task = {
				["Pirate Millionaire"] = 8
			},
			Reward = {
				Beli = 13000,
				Exp = 53000000
			}
		},
		{
			LevelReq = 1525,
			Name = "Pistol Billionaire",
			Task = {
				["Pistol Billionaire"] = 8
			},
			Reward = {
				Beli = 15000,
				Exp = 55500000
			}
		},
		{
			LevelReq = 1550,
			Name = "Stone",
			Task = {
				Stone = 1
			},
			Reward = {
				Beli = 25000,
				Exp = 60000000
			}
		}
	},
	DragonCrewQuest = {
		{
			LevelReq = 1575,
			Name = "Dragon Crew Warrior",
			Task = {
				["Dragon Crew Warrior"] = 8
			},
			Reward = {
				Beli = 13000,
				Exp = 58000000
			}
		},
		{
			LevelReq = 1600,
			Name = "Dragon Crew Archer",
			Task = {
				["Dragon Crew Archer"] = 8
			},
			Reward = {
				Beli = 15000,
				Exp = 60500000
			}
		}
	},
	VenomCrewQuest = {
		{
			LevelReq = 1625,
			Name = "Hydra Enforcer",
			Task = {
				["Hydra Enforcer"] = 8
			},
			Reward = {
				Beli = 13000,
				Exp = 62500000
			}
		},
		{
			LevelReq = 1650,
			Name = "Venomous Assailant",
			Task = {
				["Venomous Assailant"] = 8
			},
			Reward = {
				Beli = 15000,
				Exp = 64500000
			}
		},
		{
			LevelReq = 1675,
			Name = "Hydra Leader",
			Task = {
				["Hydra Leader"] = 1
			},
			Reward = {
				Beli = 30000,
				Exp = 70000000
			}
		}
	},
	MarineTreeIsland = {
		{
			LevelReq = 1700,
			Name = "Marine Commodore",
			Task = {
				["Marine Commodore"] = 8
			},
			Reward = {
				Beli = 13000,
				Exp = 68000000
			}
		},
		{
			LevelReq = 1725,
			Name = "Marine Rear Admiral",
			Task = {
				["Marine Rear Admiral"] = 8
			},
			Reward = {
				Beli = 15000,
				Exp = 70500000
			}
		},
		{
			LevelReq = 1750,
			Name = "Kilo Admiral",
			Task = {
				["Kilo Admiral"] = 1
			},
			Reward = {
				Beli = 35000,
				Exp = 78000000
			}
		}
	},
	DeepForestIsland3 = {
		{
			LevelReq = 1775,
			Name = "Fishman Raider",
			Task = {
				["Fishman Raider"] = 8
			},
			Reward = {
				Beli = 13000,
				Exp = 73000000
			}
		},
		{
			LevelReq = 1800,
			Name = "Fishman Captain",
			Task = {
				["Fishman Captain"] = 8
			},
			Reward = {
				Beli = 15000,
				Exp = 75500000
			}
		}
	},
	DeepForestIsland = {
		{
			LevelReq = 1825,
			Name = "Forest Pirate",
			Task = {
				["Forest Pirate"] = 8
			},
			Reward = {
				Beli = 13000,
				Exp = 78000000
			}
		},
		{
			LevelReq = 1850,
			Name = "Mythological Pirate",
			Task = {
				["Mythological Pirate"] = 8
			},
			Reward = {
				Beli = 13000,
				Exp = 81000000
			}
		},
		{
			LevelReq = 1875,
			Name = "Captain Elephant",
			Task = {
				["Captain Elephant"] = 1
			},
			Reward = {
				Beli = 40000,
				Exp = 90000000
			}
		}
	},
	DeepForestIsland2 = {
		{
			LevelReq = 1900,
			Name = "Jungle Pirate",
			Task = {
				["Jungle Pirate"] = 8
			},
			Reward = {
				Beli = 13000,
				Exp = 85000000
			}
		},
		{
			LevelReq = 1925,
			Name = "Musketeer Pirate",
			Task = {
				["Musketeer Pirate"] = 8
			},
			Reward = {
				Beli = 15000,
				Exp = 87500000
			}
		},
		{
			LevelReq = 1950,
			Name = "Beautiful Pirate",
			Task = {
				["Beautiful Pirate"] = 1
			},
			Reward = {
				Beli = 50000,
				Exp = 100000000
			}
		}
	},
	HauntedQuest1 = {
		{
			LevelReq = 1975,
			Name = "Reborn Skeleton",
			Task = {
				["Reborn Skeleton"] = 8
			},
			Reward = {
				Beli = 13000,
				Exp = 91000000
			}
		},
		{
			LevelReq = 2000,
			Name = "Living Zombie",
			Task = {
				["Living Zombie"] = 8
			},
			Reward = {
				Beli = 13250,
				Exp = 93500000
			}
		}
	},
	HauntedQuest2 = {
		{
			LevelReq = 2025,
			Name = "Demonic Soul",
			Task = {
				["Demonic Soul"] = 8
			},
			Reward = {
				Beli = 13500,
				Exp = 96000000
			}
		},
		{
			LevelReq = 2050,
			Name = "Posessed Mummy",
			Task = {
				["Posessed Mummy"] = 8
			},
			Reward = {
				Beli = 13750,
				Exp = 98500000
			}
		}
	},
	NutsIslandQuest = {
		{
			LevelReq = 2075,
			Name = "Peanut Scout",
			Task = {
				["Peanut Scout"] = 8
			},
			Reward = {
				Beli = 14000,
				Exp = 100000000
			}
		},
		{
			LevelReq = 2100,
			Name = "Peanut President",
			Task = {
				["Peanut President"] = 8
			},
			Reward = {
				Beli = 14100,
				Exp = 102500000
			}
		}
	},
	IceCreamIslandQuest = {
		{
			LevelReq = 2125,
			Name = "Ice Cream Chef",
			Task = {
				["Ice Cream Chef"] = 8
			},
			Reward = {
				Beli = 14200,
				Exp = 105000000
			}
		},
		{
			LevelReq = 2150,
			Name = "Ice Cream Commander",
			Task = {
				["Ice Cream Commander"] = 8
			},
			Reward = {
				Beli = 14300,
				Exp = 107500000
			}
		},
		{
			LevelReq = 2175,
			Name = "Cake Queen",
			Task = {
				["Cake Queen"] = 1
			},
			Reward = {
				Beli = 30000,
				Exp = 112500000
			}
		}
	},
	CakeQuest1 = {
		{
			LevelReq = 2200,
			Name = "Cookie Crafter",
			Task = {
				["Cookie Crafter"] = 8
			},
			Reward = {
				Beli = 14200,
				Exp = 110000000
			}
		},
		{
			LevelReq = 2225,
			Name = "Cake Guard",
			Task = {
				["Cake Guard"] = 8
			},
			Reward = {
				Beli = 14300,
				Exp = 112500000
			}
		}
	},
	CakeQuest2 = {
		{
			LevelReq = 2250,
			Name = "Baking Staff",
			Task = {
				["Baking Staff"] = 8
			},
			Reward = {
				Beli = 14400,
				Exp = 115000000
			}
		},
		{
			LevelReq = 2275,
			Name = "Head Baker",
			Task = {
				["Head Baker"] = 8
			},
			Reward = {
				Beli = 14500,
				Exp = 117500000
			}
		}
	},
	ChocQuest1 = {
		{
			LevelReq = 2300,
			Name = "Cocoa Warrior",
			Task = {
				["Cocoa Warrior"] = 8
			},
			Reward = {
				Beli = 14600,
				Exp = 120000000
			}
		},
		{
			LevelReq = 2325,
			Name = "Chocolate Bar Battler",
			Task = {
				["Chocolate Bar Battler"] = 8
			},
			Reward = {
				Beli = 14700,
				Exp = 122500000
			}
		}
	},
	ChocQuest2 = {
		{
			LevelReq = 2350,
			Name = "Sweet Thief",
			Task = {
				["Sweet Thief"] = 8
			},
			Reward = {
				Beli = 14800,
				Exp = 125000000
			}
		},
		{
			LevelReq = 2375,
			Name = "Candy Rebel",
			Task = {
				["Candy Rebel"] = 8
			},
			Reward = {
				Beli = 14900,
				Exp = 127500000
			}
		}
	},
	CandyQuest1 = {
		{
			LevelReq = 2400,
			Name = "Candy Pirate",
			Task = {
				["Candy Pirate"] = 8
			},
			Reward = {
				Beli = 14950,
				Exp = 129000000
			}
		},
		{
			LevelReq = 2425,
			Name = "Snow Demon",
			Task = {
				["Snow Demon"] = 8
			},
			Reward = {
				Beli = 15000,
				Exp = 131000000
			}
		}
	},
	TikiQuest1 = {
		{
			LevelReq = 2450,
			Name = "Isle Outlaw",
			Task = {
				["Isle Outlaw"] = 8
			},
			Reward = {
				Beli = 15100,
				Exp = 133000000
			}
		},
		{
			LevelReq = 2475,
			Name = "Island Boy",
			Task = {
				["Island Boy"] = 8
			},
			Reward = {
				Beli = 15200,
				Exp = 135000000
			}
		}
	},
	TikiQuest2 = {
		{
			LevelReq = 2500,
			Name = "Sun-kissed Warrior",
			Task = {
				["Sun-kissed Warrior"] = 8
			},
			Reward = {
				Beli = 15250,
				Exp = 137000000
			}
		},
		{
			LevelReq = 2525,
			Name = "Isle Champion",
			Task = {
				["Isle Champion"] = 8
			},
			Reward = {
				Beli = 15300,
				Exp = 139000000
			}
		}
	},
	TikiQuest3 = {
		{
			LevelReq = 2550,
			Name = "Serpent Hunter",
			Task = {
				["Serpent Hunter"] = 8
			},
			Reward = {
				Beli = 15350,
				Exp = 141000000
			}
		},
		{
			LevelReq = 2575,
			Name = "Skull Slayer",
			Task = {
				["Skull Slayer"] = 8
			},
			Reward = {
				Beli = 15400,
				Exp = 143000000
			}
		}
	},
	SubmergedQuest1 = {
		{
			LevelReq = 2600,
			Name = "Reef Bandit",
			Task = {
				["Reef Bandit"] = 8
			},
			Reward = {
				Beli = 15450,
				Exp = 145000000
			}
		},
		{
			LevelReq = 2625,
			Name = "Coral Pirate",
			Task = {
				["Coral Pirate"] = 8
			},
			Reward = {
				Beli = 15500,
				Exp = 147000000
			}
		}
	},
	SubmergedQuest2 = {
		{
			LevelReq = 2650,
			Name = "Sea Chanter",
			Task = {
				["Sea Chanter"] = 8
			},
			Reward = {
				Beli = 15550,
				Exp = 150000000
			}
		},
		{
			LevelReq = 2675,
			Name = "Ocean Prophet",
			Task = {
				["Ocean Prophet"] = 8
			},
			Reward = {
				Beli = 15600,
				Exp = 152000000
			}
		}
	},
	SubmergedQuest3 = {
		{
			LevelReq = 2675,
			Name = "High Disciple",
			Task = {
				["High Disciple"] = 8
			},
			Reward = {
				Beli = 15650,
				Exp = 154000000
			}
		},
		{
			LevelReq = 2700,
			Name = "Grand Devotee",
			Task = {
				["Grand Devotee"] = 8
			},
			Reward = {
				Beli = 15700,
				Exp = 156000000
			}
		}
	},
	BartiloQuest = {
		{
			LevelReq = 850,
			Name = "Swan\'s Raid",
			Task = {
				["Swan Pirate"] = 50
			},
			Reward = {
				Beli = 50000,
				Exp = 35000000
			},
			MeetsRequirements = function(p1) --[[ MeetsRequirements | Line: 1418 ]]
				return not p1.getSession().Data.BartiloQuest.KilledBandits
			end,
			OnComplete = function(p1) --[[ OnComplete | Line: 1422 ]]
				local Data = p1.getSession().Data

				if Data.BartiloQuest.KilledBandits then
					return
				end

				Data.BartiloQuest.KilledBandits = true
				p1.notify("Well done! Talk to Bartilo again.")
			end
		}
	},
	CitizenQuest = {
		{
			LevelReq = 1800,
			Name = "Town Raid",
			Task = {
				["Forest Pirate"] = 50
			},
			Reward = {
				Beli = 100000,
				Exp = 250000000
			},
			MeetsRequirements = function(p1) --[[ MeetsRequirements | Line: 1443 ]]
				return not p1.getSession().Data.CitizenQuest.KilledBandits
			end,
			OnComplete = function(p1) --[[ OnComplete | Line: 1447 ]]
				local Data = p1.getSession().Data

				if Data.CitizenQuest.KilledBandits then
					return
				end

				Data.CitizenQuest.KilledBandits = true
				p1.notify("Well done! Talk to Citizen again.")
			end
		}
	}
}

local BUNDLED_PUCKUI = [===[--[[
    PuckUI v3.8.0 - Motion & Transition Polish
    Shared PuckAFK game-script UI.

    v3.7.1 change: dragging via the title bar now clamps live to the
    viewport (same margin math as ClampToViewport), so the window can
    no longer be dragged partially or fully off any screen edge.

    v3.7.2 change: shrinking/resizing the game window (ViewportSize or
    CurrentCamera change) now re-clamps the window into the new bounds.

    v3.7.3 change: viewport resize handling now waits across multiple render
    frames and clamps from Main.AbsolutePosition / Main.AbsoluteSize after the
    responsive layout has actually settled. This fixes fullscreen -> small
    window resizing where Roblox reports intermediate/stale dimensions.

    v3.8.0 change: adds a lightweight motion system for minimize/restore,
    tab switching, UI visibility, toggles, dropdowns, and interaction feedback.
    Motion stays intentionally fast so the interface feels responsive rather
    than decorative or sluggish.

    Combined from both supplied PuckUI variants:
      - Uses the fuller v2.2 control/API implementation as the functional base
      - Uses the tighter v3.0 "Exact Replica" palette and visual treatment
      - Keeps notifications, close/minimize, labels, paragraphs, dividers,
        inputs, refreshable dropdowns, setters/getters, and touch support
      - Keeps the compact dark/floral Aztup-style presentation
]]

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local PuckUI = {
    Version = "3.8.0",
    Flags = {},
    Window = nil,
}

local Theme = {
    -- v3 "Exact Replica" palette
    Main = Color3.fromRGB(12, 12, 12),
    Top = Color3.fromRGB(12, 12, 12),
    Tab = Color3.fromRGB(12, 12, 12),
    Section = Color3.fromRGB(18, 18, 18),
    SectionInner = Color3.fromRGB(18, 18, 18),
    Element = Color3.fromRGB(24, 24, 24),
    ElementHover = Color3.fromRGB(32, 32, 32),
    Border = Color3.fromRGB(45, 45, 45),
    BorderDark = Color3.fromRGB(5, 5, 5),
    Text = Color3.fromRGB(170, 170, 170),
    DimText = Color3.fromRGB(100, 100, 100),
    BrightText = Color3.fromRGB(230, 230, 230),
    Accent = Color3.fromRGB(0, 95, 255),

    -- Kept from the fuller build for APIs/notifications that use semantic colors.
    Danger = Color3.fromRGB(180, 58, 64),
    Success = Color3.fromRGB(48, 145, 78),
}

PuckUI.Theme = Theme

-- One keybind state shared by every PuckAFK UI loaded in this Roblox session.
-- Changing it from any script's Settings tab immediately updates every other
-- currently-loaded PuckUI window as well.
local function getSharedEnvironment()
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" then
            return env
        end
    end

    return _G
end

local SharedEnvironment = getSharedEnvironment()
SharedEnvironment.__PUCKAFK_UI_SHARED_STATE =
    SharedEnvironment.__PUCKAFK_UI_SHARED_STATE
    or {
        ToggleKeyName = "K",
        Windows = setmetatable({}, {__mode = "k"}),
        CapturingWindow = nil,
        CapturingControl = nil,
        SuppressToggleUntil = 0,
        LayoutMode = "Auto",
        UIScalePercent = 100,
    }

local SharedUIState = SharedEnvironment.__PUCKAFK_UI_SHARED_STATE
SharedUIState.ToggleKeyName = SharedUIState.ToggleKeyName or "K"
SharedUIState.Windows = SharedUIState.Windows or setmetatable({}, {__mode = "k"})
SharedUIState.SuppressToggleUntil = SharedUIState.SuppressToggleUntil or 0
SharedUIState.LayoutMode = tostring(SharedUIState.LayoutMode or "Auto")
SharedUIState.UIScalePercent = math.clamp(tonumber(SharedUIState.UIScalePercent) or 100, 75, 125)

-- Shared persistent-config defaults used by every PuckAFK UI.
-- The Hub can override these values in getgenv() before a game script starts,
-- but direct script execution gets the same defaults.
SharedEnvironment.__PUCKAFK_CONFIG_SHARED_STATE =
    SharedEnvironment.__PUCKAFK_CONFIG_SHARED_STATE
    or {
        Root = "PuckAFK/Configs",
        AutoSaveDefault = true,
        AutoLoadDefault = true,
    }

local SharedConfigState = SharedEnvironment.__PUCKAFK_CONFIG_SHARED_STATE
SharedConfigState.Root = tostring(SharedConfigState.Root or "PuckAFK/Configs")
if SharedConfigState.AutoSaveDefault == nil then
    SharedConfigState.AutoSaveDefault = true
end
if SharedConfigState.AutoLoadDefault == nil then
    SharedConfigState.AutoLoadDefault = true
end

local FileAPI = {
    Write = type(writefile) == "function" and writefile or nil,
    Read = type(readfile) == "function" and readfile or nil,
    IsFile = type(isfile) == "function" and isfile or nil,
    MakeFolder = type(makefolder) == "function" and makefolder or nil,
    ListFiles = type(listfiles) == "function" and listfiles or nil,
    DeleteFile = type(delfile) == "function" and delfile or nil,
}

local function sanitizeFileComponent(value, fallback)
    local text = tostring(value or "")
    text = text:gsub("[^%w%-%._ ]", "_")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("%s+", "_")
    text = text:gsub("_+", "_")

    if text == "" then
        text = tostring(fallback or "default")
    end

    return text:sub(1, 80)
end

local function ensureFolderPath(path)
    if not FileAPI.MakeFolder then
        return false
    end

    local current = ""
    for part in tostring(path):gmatch("[^/\\]+") do
        current = current == "" and part or (current .. "/" .. part)
        pcall(FileAPI.MakeFolder, current)
    end

    return true
end

local function jsonDecode(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end

    local ok, value = pcall(function()
        return HttpService:JSONDecode(text)
    end)

    return ok and value or nil
end

local function jsonEncode(value)
    local ok, text = pcall(function()
        return HttpService:JSONEncode(value)
    end)

    return ok and text or nil
end

local function normalizeLayoutMode(value)
    local text = tostring(value or "Auto")
    local lowered = string.lower(text)
    if lowered == "phone" or lowered == "mobile" then
        return "Phone"
    elseif lowered == "desktop" or lowered == "pc" then
        return "Desktop"
    end
    return "Auto"
end

local function getViewportSize()
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    if viewport.X < 1 or viewport.Y < 1 then
        return Vector2.new(1280, 720)
    end
    return viewport
end

local function resolveLayoutMode(mode, viewport)
    mode = normalizeLayoutMode(mode)
    if mode ~= "Auto" then
        return mode
    end

    viewport = viewport or getViewportSize()
    local smallViewport = viewport.X < 760 or viewport.Y < 500
    local touchPhone = UserInputService.TouchEnabled
        and math.min(viewport.X, viewport.Y) <= 720

    return (smallViewport or touchPhone) and "Phone" or "Desktop"
end

local UI_PREFS_PATH = SharedConfigState.Root .. "/_ui_layout.json"

local function loadSharedUIPreferences()
    if not FileAPI.Read or not FileAPI.IsFile then
        return
    end

    local okExists, exists = pcall(FileAPI.IsFile, UI_PREFS_PATH)
    if not okExists or not exists then
        return
    end

    local okRead, text = pcall(FileAPI.Read, UI_PREFS_PATH)
    if not okRead then
        return
    end

    local data = jsonDecode(text)
    if type(data) ~= "table" then
        return
    end

    SharedUIState.LayoutMode = normalizeLayoutMode(data.LayoutMode or SharedUIState.LayoutMode)
    SharedUIState.UIScalePercent = math.clamp(
        tonumber(data.UIScalePercent) or SharedUIState.UIScalePercent or 100,
        75,
        125
    )
end

local function saveSharedUIPreferences()
    if not FileAPI.Write or not FileAPI.MakeFolder then
        return false
    end

    ensureFolderPath(SharedConfigState.Root)
    local encoded = jsonEncode({
        Version = 1,
        LayoutMode = normalizeLayoutMode(SharedUIState.LayoutMode),
        UIScalePercent = math.clamp(tonumber(SharedUIState.UIScalePercent) or 100, 75, 125),
    })

    return encoded ~= nil and pcall(FileAPI.Write, UI_PREFS_PATH, encoded)
end

loadSharedUIPreferences()

local function create(className, properties)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        object[key] = value
    end
    return object
end

local function tween(object, duration, properties)
    local animation = TweenService:Create(
        object,
        TweenInfo.new(duration or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        properties
    )
    animation:Play()
    return animation
end

-- Shared motion timings. These are deliberately short: enough to communicate
-- state changes without making frequent UI actions feel delayed.
local Motion = {
    Hover = 0.08,
    Press = 0.07,
    Toggle = 0.11,
    Popup = 0.12,
    Tab = 0.16,
    Window = 0.19,
    Visibility = 0.14,
}

local function motionTween(object, duration, style, direction, properties)
    if not object or not object.Parent then
        return nil
    end

    local animation = TweenService:Create(
        object,
        TweenInfo.new(
            duration or Motion.Tab,
            style or Enum.EasingStyle.Quart,
            direction or Enum.EasingDirection.Out
        ),
        properties
    )
    animation:Play()
    return animation
end

local function codeLabel(parent, text, size, color, zIndex)
    return create("TextLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = tostring(text or ""),
        TextColor3 = color or Theme.Text,
        TextSize = size or 12,
        Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = zIndex or 4,
        Parent = parent,
    })
end

local function getGuiParent(screenGui)
    -- Prefer PlayerGui. Some executor/plugin environments allow the initial
    -- load thread to touch CoreGui/gethui(), but later task.spawn callbacks run
    -- with a lower capability and then fail when updating those descendants.
    -- PlayerGui keeps every UI instance accessible from normal game threads.
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui and LocalPlayer then
        playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
    end

    if playerGui then
        local ok = pcall(function()
            screenGui.Parent = playerGui
        end)
        if ok and screenGui.Parent == playerGui then
            return playerGui
        end
    end

    -- Compatibility fallback only when PlayerGui is genuinely unavailable.
    if type(gethui) == "function" then
        local ok, target = pcall(gethui)
        if ok and target then
            local parented = pcall(function()
                screenGui.Parent = target
            end)
            if parented then
                return target
            end
        end
    end

    return nil
end

local function normalizeDropdownValue(value)
    if type(value) == "table" then
        return value[1]
    end
    return value
end

local function safeCallback(callback, ...)
    if type(callback) == "function" then
        task.spawn(callback, ...)
    end
end

-- Runtime-safe property update for live labels/paragraphs. This is intentionally
-- used by public Set() methods because they are often called from farm worker
-- threads long after the UI was created.
local function safeSet(instance, property, value)
    if not instance then
        return false
    end

    local ok = pcall(function()
        instance[property] = value
    end)
    return ok
end

local function setHover(button, normal, hover)
    local hovering = false

    button.MouseEnter:Connect(function()
        hovering = true
        if button.Parent then
            tween(button, Motion.Hover, {BackgroundColor3 = hover})
        end
    end)

    button.MouseLeave:Connect(function()
        hovering = false
        if button.Parent then
            tween(button, Motion.Hover, {BackgroundColor3 = normal})
        end
    end)

    button.MouseButton1Down:Connect(function()
        if button.Parent then
            motionTween(
                button,
                Motion.Press,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out,
                {BackgroundTransparency = math.min(0.12, button.BackgroundTransparency + 0.08)}
            )
        end
    end)

    button.MouseButton1Up:Connect(function()
        if button.Parent then
            motionTween(
                button,
                Motion.Press,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out,
                {BackgroundTransparency = 0}
            )
            tween(button, Motion.Hover, {BackgroundColor3 = hovering and hover or normal})
        end
    end)
end

local function getCurrentSection(tab)
    if tab._currentSection then
        return tab._currentSection
    end
    return tab:CreateSection("Main")
end

function PuckUI:SetAccent(color)
    if typeof(color) ~= "Color3" then
        return
    end

    Theme.Accent = color

    local window = self.Window
    if not window then
        return
    end

    for _, object in ipairs(window.AccentObjects or {}) do
        if object and object.Parent then
            if object:IsA("TextLabel") or object:IsA("TextButton") then
                object.TextColor3 = color
            elseif object:IsA("ImageLabel") or object:IsA("ImageButton") then
                object.ImageColor3 = color
            elseif object:IsA("GuiObject") then
                object.BackgroundColor3 = color
            end
        end
    end

    if window.CurrentTab and window.CurrentTab.Highlight then
        window.CurrentTab.Highlight.BackgroundColor3 = color
    end
end

function PuckUI:Notify(data)
    local window = self.Window
    if not window or not window.ScreenGui or not window.ScreenGui.Parent then
        return
    end

    data = data or {}

    local viewport = getViewportSize()
    local phoneLayout = resolveLayoutMode(SharedUIState.LayoutMode, viewport) == "Phone"
    local toastWidth = math.min(phoneLayout and 330 or 280, math.max(220, viewport.X - 24))
    local toastHeight = phoneLayout and 64 or 56

    local toast = create("Frame", {
        Size = UDim2.fromOffset(toastWidth, toastHeight),
        BackgroundColor3 = Theme.Section,
        BorderColor3 = Theme.Border,
        BorderSizePixel = 1,
        ZIndex = 700,
        Parent = window.NotificationHolder,
    })

    create("Frame", {
        Position = UDim2.fromOffset(1, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BackgroundTransparency = 1,
        BorderColor3 = Theme.BorderDark,
        BorderSizePixel = 1,
        ZIndex = 701,
        Parent = toast,
    })

    local accent = create("Frame", {
        Position = UDim2.fromOffset(4, 4),
        Size = UDim2.new(0, 2, 1, -8),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 702,
        Parent = toast,
    })
    table.insert(window.AccentObjects, accent)

    local title = codeLabel(toast, data.Title or "PuckAFK", phoneLayout and 14 or 12, Theme.BrightText, 703)
    title.Position = UDim2.fromOffset(12, 5)
    title.Size = UDim2.new(1, -18, 0, phoneLayout and 21 or 18)

    local content = codeLabel(toast, data.Content or "", phoneLayout and 12 or 11, Theme.DimText, 703)
    content.Position = UDim2.fromOffset(12, phoneLayout and 27 or 22)
    content.Size = UDim2.new(1, -18, 0, phoneLayout and 31 or 28)
    content.TextWrapped = true
    content.TextYAlignment = Enum.TextYAlignment.Top

    toast.BackgroundTransparency = 1
    title.TextTransparency = 1
    content.TextTransparency = 1
    accent.BackgroundTransparency = 1

    tween(toast, 0.12, {BackgroundTransparency = 0})
    tween(title, 0.12, {TextTransparency = 0})
    tween(content, 0.12, {TextTransparency = 0})
    tween(accent, 0.12, {BackgroundTransparency = 0})

    task.delay(tonumber(data.Duration) or 3, function()
        if not toast.Parent then return end
        tween(toast, 0.12, {BackgroundTransparency = 1})
        tween(title, 0.12, {TextTransparency = 1})
        tween(content, 0.12, {TextTransparency = 1})
        tween(accent, 0.12, {BackgroundTransparency = 1})
        task.wait(0.14)
        if toast.Parent then
            toast:Destroy()
        end
    end)
end

function PuckUI:CreateWindow(settings)
    settings = settings or {}

    if self.Window and self.Window.ScreenGui then
        pcall(function()
            self.Window.ScreenGui:Destroy()
        end)
    end

    local width = tonumber(settings.Width) or 480
    local height = tonumber(settings.Height) or 540
    width = math.max(320, width)
    height = math.max(320, height)

    local screen = create("ScreenGui", {
        Name = settings.GuiName or "PuckAFK_UI",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 10000,
    })
    getGuiParent(screen)

    -- Dedicated unscaled mover. Dragging changes ONLY this object's Position.
    -- The visible UI, UIScale, responsive sizing and shadow all live underneath
    -- it, so none of those systems can interfere with pointer coordinates.
    local mover = create("Frame", {
        Name = "WindowMover",
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Active = false,
        ClipsDescendants = false,
        ZIndex = 1,
        Parent = screen,
    })

    local shadow = create("Frame", {
        Name = "Shadow",
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.fromOffset(4, 4),
        Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        ZIndex = 1,
        Parent = mover,
    })

    local main = create("CanvasGroup", {
        Name = "Main",
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = Theme.Main,
        BorderColor3 = Theme.BorderDark,
        BorderSizePixel = 1,
        GroupTransparency = 0,
        Active = true,
        ClipsDescendants = true,
        ZIndex = 2,
        Parent = mover,
    })

    local mainScale = create("UIScale", {Scale = 1, Parent = main})
    local shadowScale = create("UIScale", {Scale = 1, Parent = shadow})

    -- Refined procedural rose / damask background.
    -- The whole pattern is faded as one group so overlapping petals never
    -- become harsh white blobs.
    local roseBackground = create("CanvasGroup", {
        Name = "RoseBackground",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        GroupTransparency = 0.68,
        ZIndex = 3,
        Parent = main,
    })

    local themeColor = Color3.fromRGB(255, 255, 255)

    local function softPart(parent, position, anchor, size, rotation, transparency, corner)
        local part = create("Frame", {
            AnchorPoint = anchor or Vector2.new(0.5, 0.5),
            Position = position,
            Size = size,
            Rotation = rotation or 0,
            BackgroundColor3 = themeColor,
            BackgroundTransparency = transparency or 0.82,
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = parent,
        })

        create("UICorner", {
            CornerRadius = UDim.new(corner or 1, 0),
            Parent = part,
        })

        return part
    end

    local function createPetal(parent, center, width, height, rotation, transparency)
        local petal = softPart(
            parent,
            center,
            Vector2.new(0.5, 1),
            UDim2.fromOffset(width, height),
            rotation,
            transparency,
            0.5
        )

        create("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.18),
                NumberSequenceKeypoint.new(0.55, 0.42),
                NumberSequenceKeypoint.new(1, 0.78),
            }),
            Parent = petal,
        })

        return petal
    end

    local function createRose(centerX, centerY, scale, rotationOffset)
        local size = math.floor(82 * scale)
        local motif = create("Frame", {
            Name = "RoseMotif",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset(centerX, centerY),
            Size = UDim2.fromOffset(size, size),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = roseBackground,
        })

        local center = UDim2.fromScale(0.5, 0.42)

        -- Broad outer petals.  These are intentionally narrow and highly
        -- transparent so the result reads as a damask rose, not a flower icon.
        for i = 0, 5 do
            createPetal(
                motif,
                center,
                math.max(5, math.floor(14 * scale)),
                math.max(10, math.floor(22 * scale)),
                (i * 60) + rotationOffset,
                0.76
            )
        end

        -- Inner petals, offset into the gaps.
        for i = 0, 4 do
            createPetal(
                motif,
                center,
                math.max(4, math.floor(10 * scale)),
                math.max(7, math.floor(15 * scale)),
                (i * 72) + 36 + rotationOffset,
                0.70
            )
        end

        -- Small soft centre rather than a bright solid dot.
        softPart(
            motif,
            center,
            Vector2.new(0.5, 0.5),
            UDim2.fromOffset(math.max(3, math.floor(5 * scale)), math.max(3, math.floor(5 * scale))),
            0,
            0.58,
            1
        )

        -- Curved-looking damask leaves made from thin rotated pills.
        local leafY = 0.60
        softPart(
            motif,
            UDim2.new(0.5, -5 * scale, leafY, 0),
            Vector2.new(1, 0.5),
            UDim2.fromOffset(math.max(8, math.floor(17 * scale)), math.max(2, math.floor(4 * scale))),
            -32 + rotationOffset * 0.15,
            0.78,
            1
        )
        softPart(
            motif,
            UDim2.new(0.5, 5 * scale, leafY + 0.035, 0),
            Vector2.new(0, 0.5),
            UDim2.fromOffset(math.max(8, math.floor(17 * scale)), math.max(2, math.floor(4 * scale))),
            32 + rotationOffset * 0.15,
            0.78,
            1
        )

        -- Very thin fading stem.
        local stem = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0.56, 0),
            Size = UDim2.fromOffset(1, math.max(10, math.floor(24 * scale))),
            BackgroundColor3 = themeColor,
            BackgroundTransparency = 0.74,
            BorderSizePixel = 0,
            ZIndex = 2,
            Parent = motif,
        })

        create("UIGradient", {
            Rotation = 90,
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.10),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = stem,
        })
    end

    -- Wider, staggered spacing.  Centres stay inside the window so there are
    -- no ugly chopped flowers along the frame edges.
    local tileX = 138
    local tileY = 132
    local firstY = 88 -- keeps the title/tab/control area visually clean
    local row = 0

    for y = firstY, height - 34, tileY do
        local offset = (row % 2 == 0) and 0 or math.floor(tileX / 2)
        local column = 0

        for x = 50 + offset, width - 38, tileX do
            local scale = ((row + column) % 3 == 0) and 0.70 or 0.60
            local tilt = ((row + column) % 2 == 0) and -7 or 7
            createRose(x, y, scale, tilt)
            column += 1
        end

        row += 1
    end

    create("Frame", {
        Name = "InnerBorder",
        Position = UDim2.fromOffset(1, 1),
        Size = UDim2.new(1, -2, 1, -2),
        BackgroundTransparency = 1,
        BorderColor3 = Theme.Border,
        BorderSizePixel = 1,
        ZIndex = 4,
        Parent = main,
    })

    local titleBar = create("Frame", {
        Name = "TitleBar",
        Position = UDim2.fromOffset(2, 2),
        Size = UDim2.new(1, -4, 0, 24),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 8,
        Parent = main,
    })

    local titleLabel = codeLabel(titleBar, settings.Name or settings.Title or "Aztup Hub V3", 13, Theme.BrightText, 11)
    titleLabel.Position = UDim2.fromOffset(6, 0)
    titleLabel.Size = UDim2.new(1, -52, 1, 0)

    local close = create("TextButton", {
        Name = "Close",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -2, 0, 2),
        Size = UDim2.fromOffset(18, 19),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Enum.Font.Code,
        Text = "x",
        TextSize = 12,
        TextColor3 = Theme.DimText,
        ZIndex = 15,
        Parent = titleBar,
    })

    local minimize = create("TextButton", {
        Name = "Minimize",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -20, 0, 2),
        Size = UDim2.fromOffset(18, 18),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Font = Enum.Font.Code,
        Text = "-",
        TextSize = 12,
        TextColor3 = Theme.DimText,
        ZIndex = 15,
        Parent = titleBar,
    })

    local dragHandle = create("TextButton", {
        Name = "DragHandle",
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, -42, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        Active = true,
        ZIndex = 14,
        Parent = titleBar,
    })

    local accentTop = create("Frame", {
        Name = "AccentTop",
        Position = UDim2.fromOffset(2, 26),
        Size = UDim2.new(1, -4, 0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 9,
        Parent = main,
    })

    local tabBar = create("ScrollingFrame", {
        Name = "TabBar",
        Position = UDim2.fromOffset(2, 27),
        Size = UDim2.new(1, -4, 0, 22),
        BackgroundColor3 = Theme.Tab,
        -- Keep the tab strip opaque so the accent separator above it cannot
        -- visually bleed through the tab labels on phone / scaled layouts.
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        ScrollingDirection = Enum.ScrollingDirection.X,
        ScrollBarThickness = 0,
        ElasticBehavior = Enum.ElasticBehavior.Never,
        ZIndex = 8,
        Parent = main,
    })

    local tabLayout = create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 12),
        Parent = tabBar,
    })

    -- Separator under the tab row. Keeping this separate from the active-tab
    -- highlight prevents the header from looking broken when only one tab exists.
    local tabSeparatorDark = create("Frame", {
        Name = "TabSeparatorDark",
        Position = UDim2.fromOffset(2, 49),
        Size = UDim2.new(1, -4, 0, 1),
        BackgroundColor3 = Theme.BorderDark,
        BorderSizePixel = 0,
        ZIndex = 8,
        Parent = main,
    })

    local tabSeparator = create("Frame", {
        Name = "TabSeparator",
        Position = UDim2.fromOffset(2, 50),
        Size = UDim2.new(1, -4, 0, 1),
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        ZIndex = 8,
        Parent = main,
    })

    local columnsHost = create("Frame", {
        Name = "ColumnsHost",
        Position = UDim2.fromOffset(8, 57),
        Size = UDim2.new(1, -16, 1, -65),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 4,
        Parent = main,
    })

    local popupLayer = create("Frame", {
        Name = "PopupLayer",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Active = false,
        ZIndex = 500,
        Parent = screen,
    })

    local notificationHolder = create("Frame", {
        Name = "Notifications",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 10),
        Size = UDim2.fromOffset(290, 450),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 690,
        Parent = screen,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = notificationHolder,
    })

    local window = {
        ScreenGui = screen,
        Mover = mover,
        Main = main,
        TitleBar = titleBar,
        TitleLabel = titleLabel,
        TabBar = tabBar,
        ColumnsHost = columnsHost,
        PopupLayer = popupLayer,
        NotificationHolder = notificationHolder,
        AccentObjects = {accentTop},
        Tabs = {},
        CurrentTab = nil,
        OpenPopup = nil,
        CloseCallback = nil,
        Minimized = false,
        Visible = true,
        UserPositioned = false,
        FullSize = UDim2.fromOffset(width, height),
        BaseWidth = width,
        BaseHeight = height,
        MainScale = mainScale,
        ShadowScale = shadowScale,
        LayoutMode = normalizeLayoutMode(SharedUIState.LayoutMode),
        ResolvedLayout = "Desktop",
        UIScalePercent = math.clamp(tonumber(SharedUIState.UIScalePercent) or 100, 75, 125),
        ToggleKeyName = tostring(SharedUIState.ToggleKeyName or "K"),
        ToggleKeyCode = Enum.KeyCode.K,
        KeybindDisplays = {},
        ResponsiveConnections = {},
        TabAnimationGeneration = 0,
        WindowAnimationGeneration = 0,
        VisibilityAnimationGeneration = 0,
        WindowAnimating = false,
    }

    local function updateResponsiveTextSizes(phoneLayout)
        local factor = phoneLayout and 1.12 or 1
        for _, object in ipairs(screen:GetDescendants()) do
            if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
                local base = object:GetAttribute("PuckBaseTextSize")
                if not base then
                    base = object.TextSize
                    object:SetAttribute("PuckBaseTextSize", base)
                end
                object.TextSize = math.max(9, math.floor(base * factor + 0.5))
            end
        end
    end

    local function updateResponsiveRows(phoneLayout)
        local factor = phoneLayout and 1.10 or 1
        for _, object in ipairs(screen:GetDescendants()) do
            if object:IsA("GuiObject") then
                local baseHeight = object:GetAttribute("PuckControlBaseHeight")
                if baseHeight then
                    object.Size = UDim2.new(1, 0, 0, math.floor(baseHeight * factor + 0.5))
                end
            end
        end
    end

    function window:_RenderedWindowSize(boundsMode)
        local scale = 1
        if self.MainScale then
            scale = math.max(0.01, tonumber(self.MainScale.Scale) or 1)
        end

        local baseWidth = math.max(1, tonumber(self.Main.Size.X.Offset) or self.BaseWidth or 1)
        local baseHeight = math.max(1, tonumber(self.Main.Size.Y.Offset) or self.BaseHeight or 1)
        if boundsMode == "Expanded" then
            baseWidth = math.max(1, tonumber(self.FullSize.X.Offset) or baseWidth)
            baseHeight = math.max(1, tonumber(self.FullSize.Y.Offset) or baseHeight)
        end

        return Vector2.new(baseWidth * scale, baseHeight * scale)
    end

    function window:Center()
        if not self.Mover or not self.Mover.Parent then
            return
        end

        self.UserPositioned = false
        local viewport = getViewportSize()
        local size = self:_RenderedWindowSize(self.Minimized and "Current" or "Expanded")
        self.Mover.AnchorPoint = Vector2.new(0, 0)
        self.Mover.Position = UDim2.fromOffset(
            math.floor((viewport.X - size.X) * 0.5 + 0.5),
            math.floor((viewport.Y - size.Y) * 0.5 + 0.5)
        )
    end

    function window:ClampToViewport(padding, boundsMode)
        if not self.Mover or not self.Mover.Parent then
            return
        end
        if not self.UserPositioned then
            self:Center()
            return
        end

        -- Clamp the unscaled mover only. Main/Shadow positions never change.
        local viewport = getViewportSize()
        local margin = math.max(4, tonumber(padding) or 6)
        local size = self:_RenderedWindowSize(boundsMode)
        local pos = self.Mover.Position
        local x = viewport.X * pos.X.Scale + pos.X.Offset
        local y = viewport.Y * pos.Y.Scale + pos.Y.Offset
        local maxX = math.max(margin, viewport.X - size.X - margin)
        local maxY = math.max(margin, viewport.Y - size.Y - margin)
        local nx = math.clamp(x, margin, maxX)
        local ny = math.clamp(y, margin, maxY)

        if math.abs(nx - x) < 0.01 and math.abs(ny - y) < 0.01 then
            return
        end

        self.Mover.Position = UDim2.fromOffset(nx, ny)
    end

    -- Clamp from Roblox's ACTUAL rendered rectangle. This is used after a
    -- viewport resize has had time to settle, avoiding stale UIScale/layout math.
    function window:ClampRenderedToViewport(padding)
        if not self.Mover or not self.Mover.Parent or not self.Main or not self.Main.Parent then
            return
        end
        if not self.UserPositioned then
            self:Center()
            return
        end

        local viewport = getViewportSize()
        local margin = math.max(4, tonumber(padding) or 6)
        local topLeft = self.Main.AbsolutePosition
        local size = self.Main.AbsoluteSize
        local right = topLeft.X + size.X
        local bottom = topLeft.Y + size.Y
        local dx, dy = 0, 0

        if size.X + (margin * 2) <= viewport.X then
            if topLeft.X < margin then
                dx = margin - topLeft.X
            elseif right > viewport.X - margin then
                dx = (viewport.X - margin) - right
            end
        else
            -- Responsive fitting should normally prevent this, but if Roblox is
            -- still settling an intermediate oversized frame, keep its left edge
            -- reachable until the next settle pass shrinks it correctly.
            dx = margin - topLeft.X
        end

        if size.Y + (margin * 2) <= viewport.Y then
            if topLeft.Y < margin then
                dy = margin - topLeft.Y
            elseif bottom > viewport.Y - margin then
                dy = (viewport.Y - margin) - bottom
            end
        else
            dy = margin - topLeft.Y
        end

        if math.abs(dx) < 0.01 and math.abs(dy) < 0.01 then
            return
        end

        local pos = self.Mover.Position
        self.Mover.Position = UDim2.new(
            pos.X.Scale,
            pos.X.Offset + dx,
            pos.Y.Scale,
            pos.Y.Offset + dy
        )
    end

    function window:ApplyResponsiveLayout()
        if not self.ScreenGui or not self.ScreenGui.Parent then
            return
        end

        local viewport = getViewportSize()
        local requestedMode = normalizeLayoutMode(SharedUIState.LayoutMode)
        local resolved = resolveLayoutMode(requestedMode, viewport)
        local phoneLayout = resolved == "Phone"
        local scalePercent = math.clamp(tonumber(SharedUIState.UIScalePercent) or 100, 75, 125)
        local requestedScale = scalePercent / 100
        local landscape = viewport.X > viewport.Y

        local baseWidth = self.BaseWidth
        local baseHeight = self.BaseHeight
        if phoneLayout then
            if landscape then
                baseWidth = math.min(560, math.max(420, math.floor((viewport.X - 18) / math.max(requestedScale, 0.75))))
                baseHeight = math.min(370, math.max(300, math.floor((viewport.Y - 18) / math.max(requestedScale, 0.75))))
            else
                baseWidth = math.min(380, math.max(320, math.floor((viewport.X - 18) / math.max(requestedScale, 0.75))))
                baseHeight = math.min(620, math.max(430, math.floor((viewport.Y - 18) / math.max(requestedScale, 0.75))))
            end
        end

        local fitScale = math.min(
            (viewport.X - 12) / math.max(baseWidth, 1),
            (viewport.Y - 12) / math.max(baseHeight, 1)
        )
        local effectiveScale = math.max(0.60, math.min(requestedScale, fitScale))

        self.LayoutMode = requestedMode
        self.ResolvedLayout = resolved
        self.UIScalePercent = scalePercent
        self.FullSize = UDim2.fromOffset(baseWidth, baseHeight)
        self.MainScale.Scale = effectiveScale
        self.ShadowScale.Scale = effectiveScale

        local headerHeight = phoneLayout and 31 or 24
        local tabHeight = phoneLayout and 29 or 22
        local tabY = phoneLayout and 35 or 27
        local contentY = phoneLayout and 70 or 57
        local bottomPad = phoneLayout and 79 or 65

        titleBar.Size = UDim2.new(1, -4, 0, headerHeight)
        close.Size = UDim2.fromOffset(phoneLayout and 27 or 18, phoneLayout and 27 or 19)
        minimize.Position = UDim2.new(1, phoneLayout and -30 or -20, 0, 2)
        minimize.Size = UDim2.fromOffset(phoneLayout and 27 or 18, phoneLayout and 27 or 18)
        dragHandle.Size = UDim2.new(1, phoneLayout and -62 or -42, 1, 0)
        accentTop.Position = UDim2.fromOffset(2, phoneLayout and 33 or 26)
        tabBar.Position = UDim2.fromOffset(2, tabY)
        tabBar.Size = UDim2.new(1, -4, 0, tabHeight)

        -- The tab separators must follow the responsive tab bar. Leaving these
        -- at the desktop Y coordinate makes the dark line cut through Phone tabs.
        local separatorY = tabY + tabHeight
        tabSeparatorDark.Position = UDim2.fromOffset(2, separatorY)
        tabSeparator.Position = UDim2.fromOffset(2, separatorY + 1)

        columnsHost.Position = UDim2.fromOffset(phoneLayout and 5 or 8, contentY)
        columnsHost.Size = UDim2.new(1, phoneLayout and -10 or -16, 1, -bottomPad)

        for _, tab in ipairs(self.Tabs or {}) do
            if tab.Button then
                local baseTabWidth = tab.Button:GetAttribute("PuckBaseTabWidth") or tab.Button.Size.X.Offset
                tab.Button.Size = UDim2.fromOffset(baseTabWidth + (phoneLayout and 10 or 0), tabHeight)
            end
            if tab._ReflowSections then
                tab:_ReflowSections()
            end
        end

        updateResponsiveRows(phoneLayout)
        updateResponsiveTextSizes(phoneLayout)

        if self.Minimized then
            main.Size = UDim2.fromOffset(baseWidth, phoneLayout and 34 or 27)
            shadow.Size = main.Size
            -- A shadow offset looks like a black bar underneath the collapsed
            -- title bar. Hide it completely while minimized.
            shadow.Visible = false
        else
            main.Size = self.FullSize
            shadow.Size = self.FullSize
            shadow.Visible = self.Visible ~= false
        end

        notificationHolder.Size = UDim2.fromOffset(
            math.min(phoneLayout and 340 or 290, math.max(220, viewport.X - 18)),
            math.max(220, viewport.Y - 20)
        )

        if self.DeviceStatusLabel and self.DeviceStatusLabel.Set then
            local inputName = UserInputService.TouchEnabled and "Touch" or "Keyboard/Mouse"
            self.DeviceStatusLabel:Set(string.format(
                "%s • %s • %dx%d • %d%%",
                inputName,
                resolved,
                math.floor(viewport.X),
                math.floor(viewport.Y),
                scalePercent
            ))
        end

        -- Responsive reflow may resize the contents, but it never moves a window
        -- the user has dragged. Only untouched windows are re-centered.
        if not self.UserPositioned then
            self:Center()
        end
    end

    -- PuckAFK Blox Fruits integration: release per-window service input listeners.
    -- Existing Destroy already disconnects ResponsiveConnections.
    local function trackWindowConnection(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(window.ResponsiveConnections, connection)
        return connection
    end

    function window:SetLayoutMode(mode)
        SharedUIState.LayoutMode = normalizeLayoutMode(mode)
        for otherWindow in pairs(SharedUIState.Windows) do
            if otherWindow and otherWindow.ApplyResponsiveLayout then
                otherWindow:ApplyResponsiveLayout()
            end
        end
        saveSharedUIPreferences()
        return SharedUIState.LayoutMode
    end

    function window:SetUIScalePercent(value)
        SharedUIState.UIScalePercent = math.clamp(tonumber(value) or 100, 75, 125)
        for otherWindow in pairs(SharedUIState.Windows) do
            if otherWindow and otherWindow.ApplyResponsiveLayout then
                otherWindow:ApplyResponsiveLayout()
            end
        end
        saveSharedUIPreferences()
        return SharedUIState.UIScalePercent
    end

    ------------------------------------------------------------------------
    -- Shared persistent configuration
    ------------------------------------------------------------------------
    local configSettings = type(settings.Configs) == "table" and settings.Configs or {}
    local configId = sanitizeFileComponent(
        settings.ConfigId or settings.GuiName or settings.Name or settings.Title,
        "PuckAFK"
    )

    local config = {
        Enabled = settings.DisableConfigs ~= true,
        Available = false,
        Root = tostring(configSettings.Root or SharedConfigState.Root),
        Id = configId,
        Folder = "",
        MetaPath = "",
        Selected = sanitizeFileComponent(configSettings.DefaultProfile or "default", "default"),
        AutoSave = SharedConfigState.AutoSaveDefault == true,
        AutoLoad = SharedConfigState.AutoLoadDefault == true,
        Controls = {},
        LoadedValues = {},
        Applying = false,
        Ready = false,
        LastFingerprint = nil,
        StatusLabel = nil,
        ProfilesDropdown = nil,
        ProfileInput = nil,
    }

    config.Folder = config.Root .. "/" .. config.Id
    config.MetaPath = config.Folder .. "/_meta.json"
    config.Available =
        config.Enabled
        and FileAPI.Write ~= nil
        and FileAPI.Read ~= nil
        and FileAPI.IsFile ~= nil
        and FileAPI.MakeFolder ~= nil

    if configSettings.AutoSave ~= nil then
        config.AutoSave = configSettings.AutoSave == true
    end
    if configSettings.AutoLoad ~= nil then
        config.AutoLoad = configSettings.AutoLoad == true
    end

    window.Config = config

    local function configFilePath(profile)
        return config.Folder
            .. "/"
            .. sanitizeFileComponent(profile, "default")
            .. ".json"
    end

    local function setConfigStatus(text)
        local value = tostring(text or "")
        if config.StatusLabel and config.StatusLabel.Set then
            config.StatusLabel:Set(value)
        end
    end

    function window:_SaveConfigMeta()
        if not config.Available then
            return false
        end

        local encoded = jsonEncode({
            Version = 1,
            Selected = config.Selected,
            AutoSave = config.AutoSave,
            AutoLoad = config.AutoLoad,
        })

        if not encoded then
            return false
        end

        local ok = pcall(FileAPI.Write, config.MetaPath, encoded)
        return ok == true
    end

    local function loadConfigMeta()
        if not config.Available or not FileAPI.IsFile(config.MetaPath) then
            return
        end

        local ok, text = pcall(FileAPI.Read, config.MetaPath)
        if not ok then
            return
        end

        local data = jsonDecode(text)
        if type(data) ~= "table" then
            return
        end

        if data.Selected ~= nil then
            config.Selected = sanitizeFileComponent(data.Selected, "default")
        end
        if data.AutoSave ~= nil then
            config.AutoSave = data.AutoSave == true
        end
        if data.AutoLoad ~= nil then
            config.AutoLoad = data.AutoLoad == true
        end
    end

    function window:_SnapshotConfigValues()
        local values = {}

        for key, control in pairs(config.Controls) do
            if control and control.Get then
                local ok, value = pcall(function()
                    return control:Get()
                end)

                if ok then
                    local valueType = typeof(value)
                    if valueType == "boolean"
                        or valueType == "number"
                        or valueType == "string" then
                        values[key] = value
                    end
                end
            end
        end

        return values
    end

    function window:_ConfigFingerprint()
        return jsonEncode(self:_SnapshotConfigValues()) or ""
    end

    function window:_WriteConfig(profile, showNotification)
        if not config.Available then
            setConfigStatus("Configs unavailable • executor filesystem APIs missing")
            if showNotification then
                PuckUI:Notify({
                    Title = "Configs",
                    Content = "This executor does not expose writefile/readfile/makefolder.",
                    Duration = 3,
                })
            end
            return false
        end

        local cleanProfile = sanitizeFileComponent(profile or config.Selected, "default")
        config.Selected = cleanProfile
        ensureFolderPath(config.Folder)

        local payload = {
            Version = 1,
            PuckUIVersion = PuckUI.Version,
            ConfigId = config.Id,
            Profile = cleanProfile,
            Values = self:_SnapshotConfigValues(),
        }

        local encoded = jsonEncode(payload)
        if not encoded then
            setConfigStatus("Save failed • JSON encode error")
            return false
        end

        local ok, err = pcall(FileAPI.Write, configFilePath(cleanProfile), encoded)
        if not ok then
            setConfigStatus("Save failed • " .. tostring(err))
            return false
        end

        self:_SaveConfigMeta()
        config.LastFingerprint = self:_ConfigFingerprint()
        setConfigStatus("Saved • " .. cleanProfile)

        if showNotification then
            PuckUI:Notify({
                Title = "Configs",
                Content = "Saved " .. cleanProfile,
                Duration = 2,
            })
        end

        return true
    end

    function window:_ApplyConfigValues(values)
        if type(values) ~= "table" then
            return false
        end

        config.Applying = true

        for key, value in pairs(values) do
            local control = config.Controls[key]
            if control and control.Set then
                pcall(function()
                    control:Set(value)
                end)
            else
                -- Keep the value around in case this control is created later.
                config.LoadedValues[key] = value
            end
        end

        config.Applying = false
        config.LastFingerprint = self:_ConfigFingerprint()
        return true
    end

    function window:_ReadConfig(profile, showNotification)
        if not config.Available then
            setConfigStatus("Configs unavailable • executor filesystem APIs missing")
            return false
        end

        local cleanProfile = sanitizeFileComponent(profile or config.Selected, "default")
        local path = configFilePath(cleanProfile)

        if not FileAPI.IsFile(path) then
            setConfigStatus("Not found • " .. cleanProfile)
            if showNotification then
                PuckUI:Notify({
                    Title = "Configs",
                    Content = "Config not found: " .. cleanProfile,
                    Duration = 2.5,
                })
            end
            return false
        end

        local ok, text = pcall(FileAPI.Read, path)
        if not ok then
            setConfigStatus("Load failed • could not read file")
            return false
        end

        local data = jsonDecode(text)
        if type(data) ~= "table" or type(data.Values) ~= "table" then
            setConfigStatus("Load failed • invalid config file")
            return false
        end

        config.Selected = cleanProfile
        config.LoadedValues = data.Values
        self:_ApplyConfigValues(data.Values)
        self:_SaveConfigMeta()
        setConfigStatus("Loaded • " .. cleanProfile)

        if showNotification then
            PuckUI:Notify({
                Title = "Configs",
                Content = "Loaded " .. cleanProfile,
                Duration = 2,
            })
        end

        return true
    end

    function window:_DeleteConfig(profile)
        if not config.Available or not FileAPI.DeleteFile then
            setConfigStatus("Delete unavailable in this executor")
            return false
        end

        local cleanProfile = sanitizeFileComponent(profile or config.Selected, "default")
        local path = configFilePath(cleanProfile)

        if not FileAPI.IsFile(path) then
            setConfigStatus("Not found • " .. cleanProfile)
            return false
        end

        local ok = pcall(FileAPI.DeleteFile, path)
        if not ok then
            setConfigStatus("Delete failed • " .. cleanProfile)
            return false
        end

        if config.Selected == cleanProfile then
            config.Selected = "default"
        end

        self:_SaveConfigMeta()
        setConfigStatus("Deleted • " .. cleanProfile)
        return true
    end

    function window:_ListConfigProfiles()
        local found = {}
        local seen = {}

        local function add(name)
            local clean = sanitizeFileComponent(name, "default")
            if not seen[clean] then
                seen[clean] = true
                table.insert(found, clean)
            end
        end

        add(config.Selected)
        add("default")

        if config.Available and FileAPI.ListFiles then
            local ok, files = pcall(FileAPI.ListFiles, config.Folder)
            if ok and type(files) == "table" then
                for _, path in ipairs(files) do
                    local normalized = tostring(path):gsub("\\", "/")
                    local name = normalized:match("([^/]+)%.json$")
                    if name and name ~= "_meta" then
                        add(name)
                    end
                end
            end
        end

        table.sort(found)
        return found
    end

    function window:_RegisterConfigControl(tab, data, control)
        if not config.Enabled
            or not control
            or type(data) ~= "table"
            or data.NoConfig == true then
            return
        end

        local baseName = data.ConfigKey or data.Flag or data.Name or data.Text
        if baseName == nil then
            return
        end

        local key = tostring(tab.Name) .. "." .. tostring(baseName)
        if config.Controls[key] and config.Controls[key] ~= control then
            local suffix = 2
            local original = key
            while config.Controls[key] do
                key = original .. "#" .. tostring(suffix)
                suffix += 1
            end
        end

        config.Controls[key] = control

        local loaded = config.LoadedValues[key]
        if loaded ~= nil and control.Set then
            task.defer(function()
                if not control.Set then
                    return
                end

                config.Applying = true
                pcall(function()
                    control:Set(loaded)
                end)
                config.Applying = false
            end)
        end
    end

    if config.Available then
        ensureFolderPath(config.Folder)
        loadConfigMeta()

        if config.AutoLoad then
            local path = configFilePath(config.Selected)
            if FileAPI.IsFile(path) then
                local ok, text = pcall(FileAPI.Read, path)
                if ok then
                    local data = jsonDecode(text)
                    if type(data) == "table" and type(data.Values) == "table" then
                        config.LoadedValues = data.Values
                    end
                end
            end
        end
    end

    self.Window = window
    SharedUIState.Windows[window] = true

    -- Roblox desktop window resizing can report several intermediate viewport
    -- sizes. A one-shot deferred clamp may therefore use stale dimensions. Each
    -- resize starts a short settle sequence; newer resize events cancel older
    -- sequences. The working drag system is not touched by this path.
    local viewportSettleGeneration = 0

    local function settleViewportResize()
        viewportSettleGeneration += 1
        local generation = viewportSettleGeneration

        task.spawn(function()
            if not (window.ScreenGui and window.ScreenGui.Parent) then
                return
            end

            -- Apply immediately so the responsive mode/fit scale starts moving
            -- toward the new desktop-window dimensions.
            window:ApplyResponsiveLayout()

            -- Re-check for several rendered frames. This covers the camera
            -- viewport update, UIScale update and AbsoluteSize propagation.
            for pass = 1, 6 do
                RunService.RenderStepped:Wait()
                if generation ~= viewportSettleGeneration then
                    return
                end
                if not (window.ScreenGui and window.ScreenGui.Parent) then
                    return
                end

                -- Re-run layout once more after Roblox has published the new
                -- viewport, then clamp against the real rendered Main rectangle.
                if pass == 2 or pass == 4 then
                    window:ApplyResponsiveLayout()
                end

                local margin = window.Minimized and 6
                    or (window.ResolvedLayout == "Phone" and 6 or 8)
                window:ClampRenderedToViewport(margin)
            end
        end)
    end

    local function connectViewportCamera(camera)
        if not camera then
            return
        end
        table.insert(window.ResponsiveConnections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            settleViewportResize()
        end))
    end

    connectViewportCamera(workspace.CurrentCamera)
    table.insert(window.ResponsiveConnections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        connectViewportCamera(workspace.CurrentCamera)
        settleViewportResize()
    end))

    ------------------------------------------------------------------------
    -- WindowMover dragging
    --
    -- This intentionally mirrors the simple, proven dragStart/startPos/delta
    -- pattern used by established Roblox UI libraries, but applies it to an
    -- unscaled outer mover instead of the visible/scaled Main frame.
    ------------------------------------------------------------------------
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPosition = nil
    local activeTouch = nil
    local closeOpenPopup = function() end

    local function mousePosition(input)
        if input and input.UserInputType == Enum.UserInputType.Touch then
            return Vector2.new(input.Position.X, input.Position.Y)
        end
        local p = UserInputService:GetMouseLocation()
        return Vector2.new(p.X, p.Y)
    end

    local DRAG_EDGE_MARGIN = 6

    local function updateDrag(input)
        if not dragging or not dragStart or not startPosition then
            return
        end

        local current = mousePosition(input)
        local delta = current - dragStart

        -- Raw target position, before clamping.
        local targetX = startPosition.X.Offset + delta.X
        local targetY = startPosition.Y.Offset + delta.Y

        -- Clamp live, using whatever size the window is currently rendered at
        -- (minimized title bar vs full expanded window), so it can never be
        -- dragged even partially off any edge of the viewport.
        local viewport = getViewportSize()
        local size = window:_RenderedWindowSize(window.Minimized and "Current" or "Expanded")
        local margin = DRAG_EDGE_MARGIN
        local maxX = math.max(margin, viewport.X - size.X - margin)
        local maxY = math.max(margin, viewport.Y - size.Y - margin)
        local clampedX = math.clamp(targetX, margin, maxX)
        local clampedY = math.clamp(targetY, margin, maxY)

        mover.Position = UDim2.new(
            startPosition.X.Scale,
            clampedX,
            startPosition.Y.Scale,
            clampedY
        )
    end

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then

            closeOpenPopup()
            dragging = true
            window.UserPositioned = true
            dragStart = mousePosition(input)
            startPosition = mover.Position
            activeTouch = input.UserInputType == Enum.UserInputType.Touch and input or nil

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    dragInput = nil
                    dragStart = nil
                    startPosition = nil
                    activeTouch = nil
                end
            end)
        end
    end)

    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    trackWindowConnection(UserInputService.InputChanged, function(input)
        if not dragging then return end

        if activeTouch then
            if input == activeTouch then
                updateDrag(input)
            end
        elseif input.UserInputType == Enum.UserInputType.MouseMovement then
            -- Use the global mouse location so dragging remains smooth even when
            -- the cursor leaves the narrow title-bar hitbox.
            updateDrag(input)
        end
    end)

    trackWindowConnection(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or (activeTouch ~= nil and input == activeTouch) then
            dragging = false
            dragInput = nil
            dragStart = nil
            startPosition = nil
            activeTouch = nil
            -- Deliberately no clamp, re-center, tween, anchor change or Position
            -- write here. Drop means exactly drop.
        end
    end)

    ------------------------------------------------------------------------
    -- Popup management
    ------------------------------------------------------------------------
    function window:ClosePopup()
        local popup = self.OpenPopup
        self.OpenPopup = nil
        if popup and popup.Close then
            popup:Close()
        end
    end

    closeOpenPopup = function()
        window:ClosePopup()
    end

    function window:SetCloseCallback(callback)
        self.CloseCallback = callback
    end

    function window:SetTitle(text)
        self.TitleLabel.Text = tostring(text or "")
    end

    function window:SetVisible(state)
        local visible = state == true
        if self.Visible == visible and self.Main and self.Main.Visible == visible then
            return
        end

        self.VisibilityAnimationGeneration += 1
        local generation = self.VisibilityAnimationGeneration
        self.Visible = visible

        if visible then
            safeSet(self.Main, "Visible", true)
            safeSet(self.Main, "GroupTransparency", 1)

            if shadow and not self.Minimized then
                safeSet(shadow, "Visible", true)
                safeSet(shadow, "BackgroundTransparency", 1)
                motionTween(
                    shadow,
                    Motion.Visibility,
                    Enum.EasingStyle.Quad,
                    Enum.EasingDirection.Out,
                    {BackgroundTransparency = 0.5}
                )
            end

            motionTween(
                self.Main,
                Motion.Visibility,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out,
                {GroupTransparency = 0}
            )
        else
            self:ClosePopup()

            motionTween(
                self.Main,
                Motion.Visibility,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.In,
                {GroupTransparency = 1}
            )

            if shadow and shadow.Visible then
                motionTween(
                    shadow,
                    Motion.Visibility,
                    Enum.EasingStyle.Quad,
                    Enum.EasingDirection.In,
                    {BackgroundTransparency = 1}
                )
            end

            task.delay(Motion.Visibility + 0.02, function()
                if generation ~= self.VisibilityAnimationGeneration or self.Visible then
                    return
                end
                safeSet(self.Main, "Visible", false)
                if shadow then
                    safeSet(shadow, "Visible", false)
                end
            end)
        end
    end

    function window:Toggle()
        self:SetVisible(not self.Visible)
    end

    function window:_ApplyToggleKey(key)
        local keyCode

        if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
            keyCode = key
        else
            keyCode = Enum.KeyCode[tostring(key or "")]
        end

        if not keyCode or keyCode == Enum.KeyCode.Unknown then
            return false
        end

        self.ToggleKeyCode = keyCode
        self.ToggleKeyName = keyCode.Name

        for _, control in ipairs(self.KeybindDisplays or {}) do
            if control and control._SetKeyName then
                control:_SetKeyName(self.ToggleKeyName)
            end
        end

        return true
    end

    function window:SetToggleKey(key)
        local keyCode

        if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
            keyCode = key
        else
            keyCode = Enum.KeyCode[tostring(key or "")]
        end

        if not keyCode or keyCode == Enum.KeyCode.Unknown then
            return false
        end

        SharedUIState.ToggleKeyName = keyCode.Name

        -- Broadcast the new key to every PuckAFK window currently loaded.
        for otherWindow in pairs(SharedUIState.Windows) do
            if otherWindow and otherWindow._ApplyToggleKey then
                otherWindow:_ApplyToggleKey(keyCode)
            end
        end

        return true
    end

    function window:GetToggleKey()
        return self.ToggleKeyName
    end

    function window:Destroy()
        self:ClosePopup()
        SharedUIState.Windows[self] = nil

        for _, connection in ipairs(self.ResponsiveConnections or {}) do
            pcall(function() connection:Disconnect() end)
        end
        self.ResponsiveConnections = {}

        if SharedUIState.CapturingWindow == self then
            SharedUIState.CapturingWindow = nil
            SharedUIState.CapturingControl = nil
        end

        if self.ScreenGui then
            self.ScreenGui:Destroy()
        end
    end

    function window:SelectTab(tab)
        if not tab or self.CurrentTab == tab then
            return
        end

        self:ClosePopup()
        self.TabAnimationGeneration += 1
        local generation = self.TabAnimationGeneration
        local previous = self.CurrentTab
        local previousIndex = previous and tonumber(previous.Index) or tonumber(tab.Index) or 1
        local nextIndex = tonumber(tab.Index) or previousIndex
        local direction = nextIndex >= previousIndex and 1 or -1
        local travel = window.ResolvedLayout == "Phone" and 10 or 14

        -- Clean up any stale outgoing tab from a very rapid sequence of clicks.
        -- Only the immediately previous and incoming tabs participate in the
        -- transition; everything else must be non-interactive and hidden.
        for _, otherTab in ipairs(self.Tabs or {}) do
            if otherTab ~= previous and otherTab ~= tab and otherTab.Container then
                otherTab.Container.Visible = false
                otherTab.Container.GroupTransparency = 0
                otherTab.Container.Position = UDim2.fromOffset(0, 0)
                if otherTab.Highlight then
                    otherTab.Highlight.Visible = false
                    otherTab.Highlight.BackgroundTransparency = 0
                    otherTab.Highlight.Size = UDim2.new(1, 0, 0, 1)
                end
            end
        end

        self.CurrentTab = tab

        if previous then
            motionTween(
                previous.Button,
                Motion.Tab,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.Out,
                {TextColor3 = Theme.Text}
            )
            motionTween(
                previous.Highlight,
                Motion.Tab * 0.75,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.In,
                {
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0.18, 0, 0, 1),
                }
            )
            motionTween(
                previous.Container,
                Motion.Tab,
                Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out,
                {
                    GroupTransparency = 1,
                    Position = UDim2.fromOffset(-direction * travel, 0),
                }
            )
        end

        tab.Container.Visible = true
        tab.Container.GroupTransparency = 1
        tab.Container.Position = UDim2.fromOffset(direction * travel, 0)
        tab.Highlight.BackgroundColor3 = Theme.Accent
        tab.Highlight.BackgroundTransparency = 1
        tab.Highlight.Size = UDim2.new(0.18, 0, 0, 1)
        tab.Highlight.Visible = true

        motionTween(
            tab.Button,
            Motion.Tab,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out,
            {TextColor3 = Theme.Accent}
        )
        motionTween(
            tab.Highlight,
            Motion.Tab,
            Enum.EasingStyle.Quart,
            Enum.EasingDirection.Out,
            {
                BackgroundTransparency = 0,
                Size = UDim2.new(1, 0, 0, 1),
            }
        )
        motionTween(
            tab.Container,
            Motion.Tab,
            Enum.EasingStyle.Quart,
            Enum.EasingDirection.Out,
            {
                GroupTransparency = 0,
                Position = UDim2.fromOffset(0, 0),
            }
        )

        if previous then
            task.delay(Motion.Tab + 0.025, function()
                if previous ~= self.CurrentTab and previous.Container and previous.Container.Parent then
                    previous.Container.Visible = false
                    previous.Container.GroupTransparency = 0
                    previous.Container.Position = UDim2.fromOffset(0, 0)
                    previous.Highlight.Visible = false
                    previous.Highlight.BackgroundTransparency = 0
                    previous.Highlight.Size = UDim2.new(1, 0, 0, 1)
                end
            end)
        end

        task.defer(function()
            if not tab.Button.Parent then return end
            local buttonLeft = tab.Button.AbsolutePosition.X - tabBar.AbsolutePosition.X + tabBar.CanvasPosition.X
            local buttonRight = buttonLeft + tab.Button.AbsoluteSize.X
            local visibleLeft = tabBar.CanvasPosition.X
            local visibleRight = visibleLeft + tabBar.AbsoluteSize.X
            local targetX = nil

            if buttonLeft < visibleLeft then
                targetX = math.max(0, buttonLeft - 4)
            elseif buttonRight > visibleRight then
                targetX = math.max(0, buttonRight - tabBar.AbsoluteSize.X + 4)
            end

            if targetX then
                -- CanvasPosition is not tweenable reliably in every executor, so
                -- step it over a few rendered frames instead of snapping.
                local startX = tabBar.CanvasPosition.X
                local started = os.clock()
                local duration = Motion.Tab
                while tabBar.Parent and os.clock() - started < duration do
                    local alpha = math.clamp((os.clock() - started) / duration, 0, 1)
                    local eased = 1 - ((1 - alpha) ^ 3)
                    tabBar.CanvasPosition = Vector2.new(startX + (targetX - startX) * eased, 0)
                    RunService.RenderStepped:Wait()
                end
                if tabBar.Parent then
                    tabBar.CanvasPosition = Vector2.new(targetX, 0)
                end
            end
        end)
    end

    -- Resolve this window to the current shared UI key.
    if not window:_ApplyToggleKey(SharedUIState.ToggleKeyName) then
        window:_ApplyToggleKey("K")
    end

    ------------------------------------------------------------------------
    -- Tabs and controls
    ------------------------------------------------------------------------
    function window:CreateTab(tabName, _icon)
        local tab = {
            Name = tostring(tabName),
            Window = self,
            Sections = {},
            _nextColumn = 1,
            _currentSection = nil,
            Index = #self.Tabs + 1,
        }

        local textSize = TextService:GetTextSize(tab.Name, 13, Enum.Font.Code, Vector2.new(1000, 18))
        local buttonWidth = math.max(38, textSize.X + 10)

        -- New tabs always begin from the left edge. This also clears stale
        -- CanvasPosition values left over by some executor/Studio UI states.
        if #self.Tabs == 0 then
            tabBar.CanvasPosition = Vector2.new(0, 0)
        end

        local button = create("TextButton", {
            Name = "Tab_" .. tab.Name,
            LayoutOrder = #self.Tabs + 1,
            Size = UDim2.fromOffset(buttonWidth, 22),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Font = Enum.Font.Code,
            Text = tab.Name,
            TextSize = 13,
            TextColor3 = Theme.Text,
            ZIndex = 10,
            Parent = tabBar,
        })
        button:SetAttribute("PuckBaseTabWidth", buttonWidth)

        -- Aztup top/bottom highlight for active tab
        local highlight = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 1, -1),
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 11,
            Parent = button,
        })
        table.insert(window.AccentObjects, highlight)

        local container = create("CanvasGroup", {
            Name = "Content_" .. tab.Name,
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ClipsDescendants = false,
            GroupTransparency = 0,
            Visible = false,
            ZIndex = 4,
            Parent = columnsHost,
        })

        local columns = {}
        local columnLayouts = {}

        local function updateColumnCanvas(index)
            local scroll = columns[index]
            local layout = columnLayouts[index]
            if not scroll or not layout then
                return
            end

            -- Manual CanvasSize is more reliable than nested AutomaticCanvasSize
            -- when this library is used through Studio/executor environments.
            local contentHeight = math.max(0, layout.AbsoluteContentSize.Y + 14)
            scroll.CanvasSize = UDim2.fromOffset(0, contentHeight)
        end

        for index = 1, 2 do
            local leftSide = index == 1
            local scroll = create("ScrollingFrame", {
                Name = "Column" .. tostring(index),
                Position = UDim2.new(leftSide and 0 or 0.5, leftSide and 0 or 4, 0, 0),
                Size = UDim2.new(0.5, -4, 1, 0),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.None,
                ScrollBarThickness = 2,
                ScrollBarImageColor3 = Color3.fromRGB(60, 60, 60),
                ScrollingDirection = Enum.ScrollingDirection.Y,
                ElasticBehavior = Enum.ElasticBehavior.Never,
                ClipsDescendants = true,
                ZIndex = 4,
                Parent = container,
            })

            local layout = create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 8),
                Parent = scroll,
            })

            create("UIPadding", {
                PaddingTop = UDim.new(0, 8),
                PaddingRight = UDim.new(0, leftSide and 3 or 0),
                PaddingBottom = UDim.new(0, 6),
                Parent = scroll,
            })

            layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                updateColumnCanvas(index)
            end)

            scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
                if window.OpenPopup then
                    window:ClosePopup()
                end
            end)

            columns[index] = scroll
            columnLayouts[index] = layout
        end

        tab.Button = button
        tab.Highlight = highlight
        tab.Container = container
        tab.Columns = columns

        -- Reflow rules:
        --   1 section  -> one full-width column (fixes the giant empty right side)
        --   2+ sections -> stable two-column alternating layout
        -- We do not use AbsoluteContentSize to choose a column at creation time,
        -- because Roblox may not update it until a later render step.
        local function reflowSections()
            local count = #tab.Sections
            local phoneLayout = window.ResolvedLayout == "Phone"

            if phoneLayout or count <= 1 then
                columns[1].Visible = true
                columns[1].Position = UDim2.new(0, 0, 0, 0)
                columns[1].Size = UDim2.new(1, 0, 1, 0)
                columns[2].Visible = false
                columns[2].CanvasPosition = Vector2.new(0, 0)

                for _, existingSection in ipairs(tab.Sections) do
                    if existingSection.Frame.Parent ~= columns[1] then
                        existingSection.Frame.Parent = columns[1]
                    end
                end
            else
                columns[1].Visible = true
                columns[2].Visible = true
                columns[1].Position = UDim2.new(0, 0, 0, 0)
                columns[1].Size = UDim2.new(0.5, -4, 1, 0)
                columns[2].Position = UDim2.new(0.5, 4, 0, 0)
                columns[2].Size = UDim2.new(0.5, -4, 1, 0)

                for sectionIndex, existingSection in ipairs(tab.Sections) do
                    local targetColumn = ((sectionIndex - 1) % 2) + 1
                    if existingSection.Frame.Parent ~= columns[targetColumn] then
                        existingSection.Frame.Parent = columns[targetColumn]
                    end
                end
            end

            task.defer(function()
                updateColumnCanvas(1)
                updateColumnCanvas(2)
            end)
        end

        tab._ReflowSections = reflowSections

        function tab:CreateSection(sectionName, collapsedByDefault)
            local section = {
                Name = tostring(sectionName or "Section"),
                Tab = self,
                Collapsed = collapsedByDefault == true,
            }

            local frame = create("Frame", {
                Name = "Section_" .. section.Name,
                Size = UDim2.new(1, -2, 0, 24),
                BackgroundColor3 = Theme.SectionInner,
                BackgroundTransparency = 0.5,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                ClipsDescendants = false,
                ZIndex = 5,
                Parent = columns[1],
            })

            create("UIStroke", {
                Color = Theme.Border,
                Thickness = 1,
                Parent = frame,
            })

            -- Section accent is a real top border. The title sits below it rather
            -- than being centred on the line, which avoids the line-through-text
            -- look at phone resolutions and non-100% UI scales.
            local topAccentLine = create("Frame", {
                Position = UDim2.fromOffset(0, 0),
                Size = UDim2.new(1, 0, 0, 1),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                ZIndex = 7,
                Parent = frame,
            })
            table.insert(window.AccentObjects, topAccentLine)

            local titleWidth = TextService:GetTextSize(section.Name, 12, Enum.Font.Code, Vector2.new(1000, 16)).X + 6

            local headerPatch = create("Frame", {
                Position = UDim2.fromOffset(8, 3),
                Size = UDim2.fromOffset(titleWidth, 16),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ZIndex = 7,
                Parent = frame,
            })

            local header = codeLabel(headerPatch, section.Name, 12, Theme.Text, 8)
            header.Position = UDim2.fromOffset(0, 0)
            header.Size = UDim2.new(1, 0, 1, 0)
            header.TextXAlignment = Enum.TextXAlignment.Left

            local collapseButton = create("TextButton", {
                Name = "Collapse",
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -6, 0, 2),
                Size = UDim2.fromOffset(20, 18),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Font = Enum.Font.Code,
                Text = section.Collapsed and "+" or "-",
                TextSize = 14,
                TextColor3 = Theme.DimText,
                ZIndex = 9,
                Parent = frame,
            })

            local body = create("Frame", {
                Name = "Body",
                Position = UDim2.fromOffset(8, 22),
                Size = UDim2.new(1, -16, 0, 0),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ClipsDescendants = false,
                ZIndex = 6,
                Parent = frame,
            })

            local bodyLayout = create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 4),
                Parent = body,
            })

            create("UIPadding", {
                PaddingBottom = UDim.new(0, 8),
                Parent = body,
            })

            local function updateSectionSize()
                local bodyHeight = math.max(0, bodyLayout.AbsoluteContentSize.Y + 8)
                body.Visible = not section.Collapsed
                body.Size = UDim2.new(1, -16, 0, section.Collapsed and 0 or bodyHeight)
                frame.Size = UDim2.new(1, -2, 0, section.Collapsed and 24 or math.max(36, 22 + bodyHeight))
                collapseButton.Text = section.Collapsed and "+" or "-"
            end

            collapseButton.MouseButton1Click:Connect(function()
                section.Collapsed = not section.Collapsed
                updateSectionSize()
                task.defer(function()
                    updateColumnCanvas(1)
                    updateColumnCanvas(2)
                end)
            end)

            bodyLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
                updateSectionSize()
                task.defer(function()
                    updateColumnCanvas(1)
                    updateColumnCanvas(2)
                end)
            end)

            section.Frame = frame
            section.Body = body

            function section:Set(newName)
                self.Name = tostring(newName or "")
                header.Text = self.Name
                local newWidth = TextService:GetTextSize(self.Name, 12, Enum.Font.Code, Vector2.new(1000, 16)).X + 6
                headerPatch.Size = UDim2.fromOffset(newWidth, 14)
            end

            function section:SetCollapsed(value)
                self.Collapsed = value == true
                updateSectionSize()
                task.defer(function()
                    updateColumnCanvas(1)
                    updateColumnCanvas(2)
                end)
            end

            function section:Toggle()
                self:SetCollapsed(not self.Collapsed)
            end

            table.insert(self.Sections, section)
            self._currentSection = section
            reflowSections()

            task.defer(updateSectionSize)
            return section
        end

        local function addControlFrame(height)
            local section = getCurrentSection(tab)
            local phoneFactor = window.ResolvedLayout == "Phone" and 1.10 or 1
            local row = create("Frame", {
                Size = UDim2.new(1, 0, 0, math.floor(height * phoneFactor + 0.5)),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ClipsDescendants = false,
                ZIndex = 6,
                Parent = section.Body,
            })
            row:SetAttribute("PuckControlBaseHeight", height)
            return row
        end

        function tab:CreateDivider()
            local row = addControlFrame(9)
            local divider = create("Frame", {
                Position = UDim2.fromOffset(0, 4),
                Size = UDim2.new(1, 0, 0, 1),
                BackgroundColor3 = Theme.Border,
                BorderSizePixel = 0,
                ZIndex = 7,
                Parent = row,
            })

            local object = {}
            function object:Set(visible)
                divider.Visible = visible ~= false
            end
            return object
        end

        function tab:CreateLabel(text, _icon, color)
            local row = addControlFrame(17)
            local label = codeLabel(row, text, 11, color or Theme.DimText, 7)
            label.Size = UDim2.fromScale(1, 1)
            label.TextTruncate = Enum.TextTruncate.AtEnd

            local object = {
                Label = label,
            }

            function object:Set(value, _newIcon, newColor)
                safeSet(label, "Text", tostring(value or ""))
                if typeof(newColor) == "Color3" then
                    safeSet(label, "TextColor3", newColor)
                end
            end

            return object
        end

        function tab:CreateParagraph(data)
            data = data or {}

            local contentText = tostring(data.Content or "")
            local rowHeight = tonumber(data.Height) or 50
            if #contentText > 140 then
                rowHeight = 68
            elseif #contentText > 75 then
                rowHeight = 58
            end

            local row = addControlFrame(rowHeight)

            local title = codeLabel(row, data.Title or "", 12, Theme.BrightText, 7)
            title.Position = UDim2.fromOffset(0, 0)
            title.Size = UDim2.new(1, 0, 0, 16)

            local body = codeLabel(row, contentText, 11, Theme.DimText, 7)
            body.Position = UDim2.fromOffset(0, 16)
            body.Size = UDim2.new(1, 0, 1, -16)
            body.TextWrapped = true
            body.TextYAlignment = Enum.TextYAlignment.Top

            local object = {}
            function object:Set(nextData)
                if type(nextData) == "table" then
                    if nextData.Title ~= nil then
                        safeSet(title, "Text", tostring(nextData.Title))
                    end
                    if nextData.Content ~= nil then
                        safeSet(body, "Text", tostring(nextData.Content))
                    end
                else
                    safeSet(body, "Text", tostring(nextData or ""))
                end
            end

            return object
        end

        function tab:CreateButton(data)
            data = data or {}

            -- Legacy scripts used dedicated Hide UI buttons. The UI keybind in
            -- Settings replaces them, so suppress those buttons automatically.
            local requestedName = tostring(data.Name or data.Text or "Button")
            local normalizedName = string.lower(requestedName)
            normalizedName = normalizedName:gsub("%s+", " ")

            local legacyUIButtons = {
                ["hide ui"] = true,
                ["toggle ui"] = true,
                ["hide/show ui"] = true,
                ["show/hide ui"] = true,
                ["hide / show ui"] = true,
                ["show / hide ui"] = true,
            }

            if legacyUIButtons[normalizedName] then
                local hiddenObject = {}
                function hiddenObject:Set(_value) end
                function hiddenObject:SetText(_value) end
                function hiddenObject:Get() return false end
                return hiddenObject
            end

            local row = addControlFrame(24)

            local buttonControl = create("TextButton", {
                Position = UDim2.fromOffset(0, 1),
                Size = UDim2.new(1, 0, 1, -2),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                AutoButtonColor = false,
                Font = Enum.Font.Code,
                Text = tostring(data.Name or data.Text or "Button"),
                TextColor3 = Theme.Text,
                TextSize = 11,
                ZIndex = 7,
                Parent = row,
            })
            setHover(buttonControl, Theme.Element, Theme.ElementHover)

            buttonControl.MouseButton1Click:Connect(function()
                safeCallback(data.Callback)
            end)

            local object = {
                Button = buttonControl,
            }

            function object:Set(value)
                buttonControl.Text = tostring(value or "")
            end

            function object:SetText(value)
                buttonControl.Text = tostring(value or "")
            end

            return object
        end

        function tab:CreateToggle(data)
            data = data or {}

            local row = addControlFrame(18)
            local state = data.CurrentValue == true
            local flag = data.Flag

            local hit = create("TextButton", {
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Text = "",
                ZIndex = 9,
                Parent = row,
            })

            local box = create("Frame", {
                Position = UDim2.fromOffset(2, 3),
                Size = UDim2.fromOffset(12, 12),
                BackgroundColor3 = Color3.fromRGB(15, 15, 15),
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                ZIndex = 7,
                Parent = row,
            })
            create("UIStroke", { Color = Theme.Border, Thickness = 1, Parent = box })

            local fill = create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = state and UDim2.new(1, -4, 1, -4) or UDim2.fromOffset(0, 0),
                BackgroundColor3 = Theme.Accent,
                BackgroundTransparency = state and 0 or 1,
                BorderSizePixel = 0,
                Visible = true,
                ZIndex = 9,
                Parent = box,
            })
            table.insert(window.AccentObjects, fill)

            local label = codeLabel(row, data.Name or data.Text or "Toggle", 12, state and Theme.BrightText or Theme.DimText, 7)
            label.Position = UDim2.fromOffset(22, 0)
            label.Size = UDim2.new(1, -22, 1, 0)
            label.TextTruncate = Enum.TextTruncate.AtEnd

            local object = {}
            local toggleGeneration = 0

            local function apply(value, invokeCallback)
                state = value == true
                toggleGeneration += 1
                local generation = toggleGeneration

                motionTween(
                    fill,
                    Motion.Toggle,
                    Enum.EasingStyle.Back,
                    Enum.EasingDirection.Out,
                    {
                        Size = state and UDim2.new(1, -4, 1, -4) or UDim2.fromOffset(0, 0),
                        BackgroundTransparency = state and 0 or 1,
                    }
                )
                motionTween(
                    label,
                    Motion.Toggle,
                    Enum.EasingStyle.Quad,
                    Enum.EasingDirection.Out,
                    {TextColor3 = state and Theme.BrightText or Theme.DimText}
                )

                if not state then
                    task.delay(Motion.Toggle + 0.02, function()
                        if generation == toggleGeneration and not state and fill.Parent then
                            fill.Size = UDim2.fromOffset(0, 0)
                            fill.BackgroundTransparency = 1
                        end
                    end)
                end

                if flag then
                    PuckUI.Flags[flag] = state
                end

                if invokeCallback then
                    safeCallback(data.Callback, state)
                end
            end

            function object:Set(value)
                apply(value, true)
            end

            function object:Get()
                return state
            end

            hit.MouseButton1Click:Connect(function()
                apply(not state, true)
            end)

            if flag then
                PuckUI.Flags[flag] = state
            end

            window:_RegisterConfigControl(tab, data, object)
            return object
        end

        function tab:CreateDropdown(data)
            data = data or {}

            local row = addControlFrame(40)
            local label = codeLabel(row, data.Name or "Dropdown", 12, Theme.Text, 7)
            label.Size = UDim2.new(1, 0, 0, 16)

            local options = {}
            for _, option in ipairs(data.Options or {}) do
                table.insert(options, option)
            end

            local current = normalizeDropdownValue(data.CurrentOption)
            if current == nil then
                current = options[1]
            end

            local selector = create("TextButton", {
                Position = UDim2.fromOffset(0, 18),
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                AutoButtonColor = false,
                Font = Enum.Font.Code,
                Text = "  " .. tostring(current or "Select..."),
                TextColor3 = Theme.Text,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 8,
                Parent = row,
            })
            setHover(selector, Theme.Element, Theme.ElementHover)

            local arrow = codeLabel(selector, "v", 10, Theme.DimText, 9)
            arrow.AnchorPoint = Vector2.new(1, 0)
            arrow.Position = UDim2.new(1, -3, 0, 0)
            arrow.Size = UDim2.fromOffset(12, 20)
            arrow.TextXAlignment = Enum.TextXAlignment.Center

            local object = {}
            local flag = data.Flag
            local popup = nil
            local blocker = nil
            local popupGeneration = 0
            local popupOpensUpward = false
            local popupTargetPosition = nil
            local popupTargetHeight = 0

            local function apply(value, invokeCallback)
                if value == nil then
                    return
                end

                current = value
                selector.Text = "  " .. tostring(current)

                if flag then
                    PuckUI.Flags[flag] = current
                end

                if invokeCallback then
                    safeCallback(data.Callback, {current})
                end
            end

            local function closePopup()
                popupGeneration += 1
                local generation = popupGeneration
                local oldPopup = popup
                popup = nil

                if blocker then
                    blocker:Destroy()
                    blocker = nil
                end

                motionTween(
                    arrow,
                    Motion.Popup,
                    Enum.EasingStyle.Quad,
                    Enum.EasingDirection.Out,
                    {Rotation = 0, TextColor3 = Theme.DimText}
                )

                if oldPopup and oldPopup.Parent then
                    local targetPosition = oldPopup.Position
                    if popupOpensUpward then
                        targetPosition = UDim2.fromOffset(
                            oldPopup.Position.X.Offset,
                            oldPopup.Position.Y.Offset + oldPopup.AbsoluteSize.Y
                        )
                    end

                    motionTween(
                        oldPopup,
                        Motion.Popup,
                        Enum.EasingStyle.Quad,
                        Enum.EasingDirection.In,
                        {
                            Size = UDim2.fromOffset(oldPopup.Size.X.Offset, 1),
                            Position = targetPosition,
                            BackgroundTransparency = 1,
                        }
                    )

                    task.delay(Motion.Popup + 0.02, function()
                        if oldPopup and oldPopup.Parent then
                            oldPopup:Destroy()
                        end
                    end)
                end

                if window.OpenPopup == object then
                    window.OpenPopup = nil
                end
            end

            function object:Close()
                closePopup()
            end

            local function openPopup()
                if window.OpenPopup and window.OpenPopup ~= object then
                    window.OpenPopup:Close()
                end

                closePopup()

                local selectorPosition = selector.AbsolutePosition
                local selectorSize = selector.AbsoluteSize
                local itemHeight = window.ResolvedLayout == "Phone" and 28 or 20
                local maxVisible = tonumber(data.MaxVisible) or (window.ResolvedLayout == "Phone" and 6 or 8)
                local visibleCount = math.min(#options, maxVisible)
                local menuHeight = math.max(itemHeight + 2, visibleCount * itemHeight + 2)

                local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
                local menuY = selectorPosition.Y + selectorSize.Y + 1
                popupOpensUpward = false

                if menuY + menuHeight > viewport.Y - 6 then
                    menuY = selectorPosition.Y - menuHeight - 1
                    popupOpensUpward = true
                end

                popupTargetPosition = UDim2.fromOffset(selectorPosition.X, menuY)
                popupTargetHeight = menuHeight

                blocker = create("TextButton", {
                    Size = UDim2.fromScale(1, 1),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Text = "",
                    ZIndex = 501,
                    Parent = popupLayer,
                })

                blocker.MouseButton1Click:Connect(closePopup)

                local popupWidth = math.max(80, selectorSize.X)
                local startY = popupOpensUpward and (menuY + menuHeight) or menuY

                popup = create("ScrollingFrame", {
                    Position = UDim2.fromOffset(selectorPosition.X, startY),
                    Size = UDim2.fromOffset(popupWidth, 1),
                    BackgroundColor3 = Color3.fromRGB(20, 20, 20),
                    BackgroundTransparency = 1,
                    BorderColor3 = Theme.Border,
                    BorderSizePixel = 1,
                    CanvasSize = UDim2.new(),
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    ScrollBarThickness = #options > maxVisible and 3 or 0,
                    ScrollBarImageColor3 = Color3.fromRGB(90, 90, 90),
                    ScrollingDirection = Enum.ScrollingDirection.Y,
                    ElasticBehavior = Enum.ElasticBehavior.Never,
                    ClipsDescendants = true,
                    ZIndex = 510,
                    Parent = popupLayer,
                })

                create("UIListLayout", {
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding = UDim.new(0, 0),
                    Parent = popup,
                })

                for index, value in ipairs(options) do
                    local optionButton = create("TextButton", {
                        LayoutOrder = index,
                        Size = UDim2.new(1, 0, 0, itemHeight),
                        BackgroundColor3 = value == current and Color3.fromRGB(38, 38, 38) or Color3.fromRGB(25, 25, 25),
                        BorderSizePixel = 0,
                        AutoButtonColor = false,
                        Font = Enum.Font.Code,
                        Text = "  " .. tostring(value),
                        TextColor3 = value == current and Theme.BrightText or Theme.Text,
                        TextSize = window.ResolvedLayout == "Phone" and 12 or 11,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        ZIndex = 512,
                        Parent = popup,
                    })

                    setHover(
                        optionButton,
                        value == current and Color3.fromRGB(38, 38, 38) or Color3.fromRGB(25, 25, 25),
                        Theme.Element
                    )

                    optionButton.MouseButton1Click:Connect(function()
                        apply(value, true)
                        closePopup()
                    end)
                end

                popupGeneration += 1
                local generation = popupGeneration

                motionTween(
                    popup,
                    Motion.Popup,
                    Enum.EasingStyle.Quart,
                    Enum.EasingDirection.Out,
                    {
                        Position = popupTargetPosition,
                        Size = UDim2.fromOffset(popupWidth, popupTargetHeight),
                        BackgroundTransparency = 0,
                    }
                )
                motionTween(
                    arrow,
                    Motion.Popup,
                    Enum.EasingStyle.Quart,
                    Enum.EasingDirection.Out,
                    {Rotation = 180, TextColor3 = Theme.BrightText}
                )

                window.OpenPopup = object
            end

            selector.MouseButton1Click:Connect(function()
                if window.OpenPopup == object then
                    closePopup()
                else
                    openPopup()
                end
            end)

            function object:Set(value)
                apply(normalizeDropdownValue(value), true)
            end

            function object:Get()
                return current
            end

            function object:Refresh(newOptions)
                closePopup()

                options = {}
                for _, option in ipairs(newOptions or {}) do
                    table.insert(options, option)
                end

                if current == nil or not table.find(options, current) then
                    current = options[1]
                    selector.Text = "  " .. tostring(current or "Select...")
                    if flag then
                        PuckUI.Flags[flag] = current
                    end
                end
            end

            if flag and current ~= nil then
                PuckUI.Flags[flag] = current
            end

            window:_RegisterConfigControl(tab, data, object)
            return object
        end

        function tab:CreateSlider(data)
            data = data or {}

            -- Sliders redesigned for Aztup format: thicker bar, value inside.
            local row = addControlFrame(34)
            local minimum = tonumber(data.Range and data.Range[1] or data.Min) or 0
            local maximum = tonumber(data.Range and data.Range[2] or data.Max) or 100
            local increment = tonumber(data.Increment) or 1
            local suffix = tostring(data.Suffix or "")

            local value = tonumber(data.CurrentValue or data.Value) or minimum
            value = math.clamp(value, minimum, maximum)

            local label = codeLabel(row, data.Name or "Slider", 11, Theme.DimText, 7)
            label.Size = UDim2.new(1, 0, 0, 14)

            local rail = create("Frame", {
                Position = UDim2.fromOffset(0, 18),
                Size = UDim2.new(1, 0, 0, 14),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                Active = true,
                ZIndex = 7,
                Parent = row,
            })

            local fill = create("Frame", {
                Size = UDim2.new((value - minimum) / math.max(maximum - minimum, 1), 0, 1, 0),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                ZIndex = 8,
                Parent = rail,
            })
            table.insert(window.AccentObjects, fill)

            -- The value label is now placed inside the rail to mimic Aztup
            local valueLabel = codeLabel(rail, tostring(value) .. suffix, 11, Theme.BrightText, 9)
            valueLabel.Size = UDim2.fromScale(1, 1)
            valueLabel.TextXAlignment = Enum.TextXAlignment.Center

            local draggingSlider = false
            local flag = data.Flag
            local object = {}

            local function apply(nextValue, invokeCallback)
                nextValue = tonumber(nextValue)
                if not nextValue then
                    return
                end

                nextValue = math.clamp(nextValue, minimum, maximum)
                nextValue = math.floor(nextValue / increment + 0.5) * increment

                if increment < 1 then
                    local decimals = math.max(0, math.ceil(-math.log10(increment)))
                    local factor = 10 ^ decimals
                    nextValue = math.floor(nextValue * factor + 0.5) / factor
                end

                value = nextValue
                valueLabel.Text = tostring(value) .. suffix
                local targetFill = UDim2.new(
                    (value - minimum) / math.max(maximum - minimum, 1),
                    0,
                    1,
                    0
                )
                if draggingSlider then
                    fill.Size = targetFill
                else
                    motionTween(
                        fill,
                        Motion.Toggle,
                        Enum.EasingStyle.Quad,
                        Enum.EasingDirection.Out,
                        {Size = targetFill}
                    )
                end

                if flag then
                    PuckUI.Flags[flag] = value
                end

                if invokeCallback then
                    safeCallback(data.Callback, value)
                end
            end

            local function fromPosition(x)
                local alpha = math.clamp(
                    (x - rail.AbsolutePosition.X) / math.max(rail.AbsoluteSize.X, 1),
                    0,
                    1
                )
                apply(minimum + (maximum - minimum) * alpha, true)
            end

            rail.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    draggingSlider = true
                    fromPosition(input.Position.X)
                end
            end)

            trackWindowConnection(UserInputService.InputChanged, function(input)
                if draggingSlider and (
                    input.UserInputType == Enum.UserInputType.MouseMovement
                    or input.UserInputType == Enum.UserInputType.Touch
                ) then
                    fromPosition(input.Position.X)
                end
            end)

            trackWindowConnection(UserInputService.InputEnded, function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    draggingSlider = false
                end
            end)

            function object:Set(nextValue)
                apply(nextValue, true)
            end

            function object:Get()
                return value
            end

            if flag then
                PuckUI.Flags[flag] = value
            end

            window:_RegisterConfigControl(tab, data, object)
            return object
        end

        function tab:CreateInput(data)
            data = data or {}

            local row = addControlFrame(40)

            local label = codeLabel(row, data.Name or "Input", 11, Theme.Text, 7)
            label.Size = UDim2.new(1, 0, 0, 16)

            local box = create("TextBox", {
                Position = UDim2.fromOffset(0, 18),
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                ClearTextOnFocus = false,
                Font = Enum.Font.Code,
                Text = tostring(data.CurrentValue or ""),
                PlaceholderText = tostring(data.PlaceholderText or ""),
                TextColor3 = Theme.Text,
                PlaceholderColor3 = Theme.DimText,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 8,
                Parent = row,
            })

            create("UIPadding", {
                PaddingLeft = UDim.new(0, 6),
                PaddingRight = UDim.new(0, 6),
                Parent = box,
            })

            local current = box.Text
            local flag = data.Flag
            local object = {}

            local function apply(value, invokeCallback)
                current = tostring(value or "")
                box.Text = current

                if flag then
                    PuckUI.Flags[flag] = current
                end

                if invokeCallback then
                    safeCallback(data.Callback, current)
                end
            end

            box.FocusLost:Connect(function()
                current = box.Text

                if flag then
                    PuckUI.Flags[flag] = current
                end

                safeCallback(data.Callback, current)

                if data.RemoveTextAfterFocusLost then
                    box.Text = ""
                end
            end)

            function object:Set(value)
                apply(value, true)
            end

            function object:Get()
                return current
            end

            if flag then
                PuckUI.Flags[flag] = current
            end

            window:_RegisterConfigControl(tab, data, object)
            return object
        end

        function tab:CreateKeybind(data)
            data = data or {}

            local row = addControlFrame(40)

            local label = codeLabel(row, data.Name or "UI Toggle Keybind", 11, Theme.Text, 7)
            label.Size = UDim2.new(1, 0, 0, 16)

            local bindButton = create("TextButton", {
                Position = UDim2.fromOffset(0, 18),
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundColor3 = Theme.Element,
                BorderColor3 = Theme.BorderDark,
                BorderSizePixel = 1,
                AutoButtonColor = false,
                Font = Enum.Font.Code,
                Text = "",
                TextColor3 = Theme.Text,
                TextSize = 11,
                ZIndex = 8,
                Parent = row,
            })
            create("UIStroke", {Color = Theme.Border, Thickness = 1, Parent = bindButton})
            setHover(bindButton, Theme.Element, Theme.ElementHover)

            local object = {
                Button = bindButton,
                Callback = data.Callback,
                CurrentKey = window.ToggleKeyName,
                Capturing = false,
            }

            function object:_SetKeyName(keyName)
                self.CurrentKey = tostring(keyName or "K")
                self.Capturing = false
                bindButton.Text = "[ " .. self.CurrentKey .. " ]"
                bindButton.TextColor3 = Theme.Text
            end

            function object:Set(value)
                local previous = window.ToggleKeyName
                if window:SetToggleKey(value) then
                    self:_SetKeyName(window.ToggleKeyName)
                    if previous ~= window.ToggleKeyName then
                        safeCallback(self.Callback, window.ToggleKeyName)
                    end
                    return true
                end
                return false
            end

            function object:Get()
                return window.ToggleKeyName
            end

            function object:CancelCapture()
                if SharedUIState.CapturingControl == self then
                    SharedUIState.CapturingControl = nil
                    SharedUIState.CapturingWindow = nil
                end
                self:_SetKeyName(window.ToggleKeyName)
            end

            bindButton.MouseButton1Click:Connect(function()
                local previousControl = SharedUIState.CapturingControl
                if previousControl and previousControl ~= object and previousControl.CancelCapture then
                    previousControl:CancelCapture()
                end

                window:ClosePopup()
                SharedUIState.CapturingWindow = window
                SharedUIState.CapturingControl = object
                object.Capturing = true
                bindButton.Text = "[ press a key... ]"
                bindButton.TextColor3 = Theme.Accent
            end)

            object:_SetKeyName(window.ToggleKeyName)
            table.insert(window.KeybindDisplays, object)

            return object
        end

        button.MouseEnter:Connect(function()
            if window.CurrentTab ~= tab and button.Parent then
                motionTween(
                    button,
                    Motion.Hover,
                    Enum.EasingStyle.Quad,
                    Enum.EasingDirection.Out,
                    {TextColor3 = Theme.BrightText}
                )
            end
        end)

        button.MouseLeave:Connect(function()
            if window.CurrentTab ~= tab and button.Parent then
                motionTween(
                    button,
                    Motion.Hover,
                    Enum.EasingStyle.Quad,
                    Enum.EasingDirection.Out,
                    {TextColor3 = Theme.Text}
                )
            end
        end)

        button.MouseButton1Click:Connect(function()
            window:SelectTab(tab)
        end)

        table.insert(self.Tabs, tab)

        -- Shared interface controls are injected into every Settings tab.
        if string.lower(tab.Name) == "settings"
            and settings.DisableBuiltInResponsiveUI ~= true then

            tab:CreateSection("Interface")

            if settings.DisableBuiltInUIKeybind ~= true then
                tab:CreateKeybind({
                    Name = "UI Toggle Keybind",
                    Callback = function(keyName)
                        PuckUI:Notify({
                            Title = "UI Keybind",
                            Content = "All PuckAFK UIs now use " .. tostring(keyName),
                            Duration = 2.5,
                        })
                    end,
                })
            end

            tab:CreateDropdown({
                Name = "UI Layout",
                Options = {"Auto", "Desktop", "Phone"},
                CurrentOption = {normalizeLayoutMode(SharedUIState.LayoutMode)},
                NoConfig = true,
                Callback = function(option)
                    local selected = normalizeDropdownValue(option)
                    window:SetLayoutMode(selected)
                end,
            })

            tab:CreateSlider({
                Name = "UI Size",
                Range = {75, 125},
                Increment = 5,
                CurrentValue = math.clamp(tonumber(SharedUIState.UIScalePercent) or 100, 75, 125),
                Suffix = "%",
                NoConfig = true,
                Callback = function(value)
                    window:SetUIScalePercent(value)
                end,
            })

            window.DeviceStatusLabel = tab:CreateLabel("Detecting display...")
            if settings.DisableBuiltInUIKeybind ~= true then
                tab:CreateLabel("Click the key box, then press any key. Escape cancels.")
            end
        end

        if string.lower(tab.Name) == "settings"
            and settings.DisableBuiltInConfigs ~= true
            and not self._CreatingConfigTab then
            task.defer(function()
                if self.ScreenGui and self.ScreenGui.Parent then
                    self:_EnsureConfigTab()
                end
            end)
        end

        if #self.Tabs == 1 then
            task.defer(function()
                if button.Parent then
                    tabBar.CanvasPosition = Vector2.new(0, 0)
                    self:SelectTab(tab)
                end
            end)
        end

        task.defer(function()
            if window.ScreenGui and window.ScreenGui.Parent then
                window:ApplyResponsiveLayout()
            end
        end)

        return tab
    end

    function window:_EnsureConfigTab()
        if self._ConfigTab or self._CreatingConfigTab or not config.Enabled then
            return self._ConfigTab
        end

        self._CreatingConfigTab = true
        local tab = self:CreateTab("Configs")
        self._CreatingConfigTab = false
        self._ConfigTab = tab

        tab:CreateSection("Profiles")

        config.StatusLabel = tab:CreateLabel(
            config.Available
                and ("Ready • " .. config.Selected)
                or "Unavailable • executor filesystem APIs missing"
        )

        if not config.Available then
            tab:CreateParagraph({
                Title = "Persistent configs unavailable",
                Content = "This executor needs writefile, readfile, isfile and makefolder for saved configs. The rest of PuckAFK still works normally.",
                Height = 64,
            })
            return tab
        end

        config.ProfilesDropdown = tab:CreateDropdown({
            Name = "Config Profile",
            Options = self:_ListConfigProfiles(),
            CurrentOption = {config.Selected},
            NoConfig = true,
            Callback = function(option)
                local value = normalizeDropdownValue(option)
                if value ~= nil then
                    config.Selected = sanitizeFileComponent(value, "default")
                    if config.ProfileInput and config.ProfileInput.Set then
                        config.ProfileInput:Set(config.Selected)
                    end
                    self:_SaveConfigMeta()
                    setConfigStatus("Selected • " .. config.Selected)
                end
            end,
        })

        config.ProfileInput = tab:CreateInput({
            Name = "Profile Name",
            CurrentValue = config.Selected,
            PlaceholderText = "default",
            NoConfig = true,
            Callback = function(value)
                config.PendingProfile = sanitizeFileComponent(value, config.Selected)
            end,
        })

        tab:CreateButton({
            Name = "Save / Create Profile",
            Callback = function()
                local profile = config.PendingProfile or config.Selected
                config.Selected = sanitizeFileComponent(profile, "default")
                self:_WriteConfig(config.Selected, true)

                if config.ProfilesDropdown and config.ProfilesDropdown.Refresh then
                    config.ProfilesDropdown:Refresh(self:_ListConfigProfiles())
                    config.ProfilesDropdown:Set(config.Selected)
                end
            end,
        })

        tab:CreateButton({
            Name = "Load Selected Profile",
            Callback = function()
                self:_ReadConfig(config.Selected, true)
            end,
        })

        tab:CreateButton({
            Name = "Refresh Profiles",
            Callback = function()
                if config.ProfilesDropdown and config.ProfilesDropdown.Refresh then
                    config.ProfilesDropdown:Refresh(self:_ListConfigProfiles())
                    config.ProfilesDropdown:Set(config.Selected)
                end
                setConfigStatus("Profiles refreshed")
            end,
        })

        tab:CreateButton({
            Name = "Delete Selected Profile",
            Callback = function()
                local deleted = config.Selected
                if self:_DeleteConfig(deleted) then
                    if config.ProfilesDropdown and config.ProfilesDropdown.Refresh then
                        config.ProfilesDropdown:Refresh(self:_ListConfigProfiles())
                        config.ProfilesDropdown:Set(config.Selected)
                    end
                    if config.ProfileInput and config.ProfileInput.Set then
                        config.ProfileInput:Set(config.Selected)
                    end
                    PuckUI:Notify({
                        Title = "Configs",
                        Content = "Deleted " .. tostring(deleted),
                        Duration = 2,
                    })
                end
            end,
        })

        tab:CreateSection("Automation")

        tab:CreateToggle({
            Name = "Auto Save",
            CurrentValue = config.AutoSave,
            NoConfig = true,
            Callback = function(value)
                config.AutoSave = value == true
                self:_SaveConfigMeta()
                if config.AutoSave then
                    self:_WriteConfig(config.Selected, false)
                end
                setConfigStatus(
                    config.AutoSave
                        and ("Auto Save ON • " .. config.Selected)
                        or "Auto Save OFF"
                )
            end,
        })

        tab:CreateToggle({
            Name = "Auto Load",
            CurrentValue = config.AutoLoad,
            NoConfig = true,
            Callback = function(value)
                config.AutoLoad = value == true
                self:_SaveConfigMeta()
                setConfigStatus(
                    config.AutoLoad
                        and ("Auto Load ON • " .. config.Selected)
                        or "Auto Load OFF"
                )
            end,
        })

        tab:CreateLabel("Auto Load restores the selected profile next run.")
        tab:CreateLabel("Auto Save writes changes after you adjust any saved control.")

        if next(config.LoadedValues) ~= nil and config.AutoLoad then
            task.defer(function()
                PuckUI:Notify({
                    Title = "Configs",
                    Content = "Auto-loaded " .. config.Selected,
                    Duration = 2.5,
                })
            end)
        end

        return tab
    end

    close.MouseEnter:Connect(function()
        if close.Parent then
            motionTween(close, Motion.Hover, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
                TextColor3 = Theme.Danger,
            })
        end
    end)

    close.MouseLeave:Connect(function()
        if close.Parent then
            motionTween(close, Motion.Hover, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
                TextColor3 = Theme.DimText,
            })
        end
    end)

    minimize.MouseEnter:Connect(function()
        if minimize.Parent then
            motionTween(minimize, Motion.Hover, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
                TextColor3 = Theme.BrightText,
            })
        end
    end)

    minimize.MouseLeave:Connect(function()
        if minimize.Parent and not window.WindowAnimating then
            motionTween(minimize, Motion.Hover, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
                TextColor3 = Theme.DimText,
            })
        end
    end)

    close.MouseButton1Click:Connect(function()
        window:ClosePopup()
        window.VisibilityAnimationGeneration += 1
        motionTween(
            main,
            Motion.Visibility,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.In,
            {GroupTransparency = 1}
        )
        if shadow.Visible then
            motionTween(
                shadow,
                Motion.Visibility,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.In,
                {BackgroundTransparency = 1}
            )
        end

        task.delay(Motion.Visibility, function()
            if window.CloseCallback then
                window.CloseCallback()
            else
                window:Destroy()
            end
        end)
    end)

    minimize.MouseButton1Click:Connect(function()
        if window.WindowAnimating then
            return
        end

        window:ClosePopup()
        window.WindowAnimationGeneration += 1
        local generation = window.WindowAnimationGeneration
        window.WindowAnimating = true
        window.Minimized = not window.Minimized

        local miniHeight = window.ResolvedLayout == "Phone" and 34 or 27

        if window.Minimized then
            minimize.Text = "+"
            motionTween(
                minimize,
                Motion.Window,
                Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out,
                {TextColor3 = Theme.BrightText, Rotation = 180}
            )

            shadow.Visible = window.Visible ~= false
            motionTween(
                shadow,
                Motion.Window * 0.8,
                Enum.EasingStyle.Quad,
                Enum.EasingDirection.In,
                {
                    Size = UDim2.fromOffset(window.FullSize.X.Offset, miniHeight),
                    BackgroundTransparency = 1,
                }
            )
            motionTween(
                main,
                Motion.Window,
                Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out,
                {Size = UDim2.fromOffset(window.FullSize.X.Offset, miniHeight)}
            )

            task.delay(Motion.Window * 0.82, function()
                if generation ~= window.WindowAnimationGeneration or not window.Minimized then
                    return
                end

                tabBar.Visible = false
                accentTop.Visible = false
                tabSeparatorDark.Visible = false
                tabSeparator.Visible = false
                columnsHost.Visible = false
            end)

            task.delay(Motion.Window + 0.025, function()
                if generation ~= window.WindowAnimationGeneration or not window.Minimized then
                    return
                end
                shadow.Visible = false
                window.WindowAnimating = false
                window:ClampToViewport(6, "Current")
            end)
        else
            -- Clamp using the future full size before the expansion starts so the
            -- window never animates off-screen and then jumps back afterward.
            window:ClampToViewport(
                window.ResolvedLayout == "Phone" and 6 or 8,
                "Expanded"
            )

            tabBar.Visible = true
            accentTop.Visible = true
            tabSeparatorDark.Visible = true
            tabSeparator.Visible = true
            columnsHost.Visible = true

            if window.CurrentTab and window.CurrentTab.Container then
                window.CurrentTab.Container.Visible = true
            end

            shadow.Visible = window.Visible ~= false
            shadow.BackgroundTransparency = 1
            shadow.Size = UDim2.fromOffset(window.FullSize.X.Offset, miniHeight)

            minimize.Text = "-"
            minimize.Rotation = 180

            motionTween(
                minimize,
                Motion.Window,
                Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out,
                {TextColor3 = Theme.DimText, Rotation = 0}
            )
            motionTween(
                shadow,
                Motion.Window,
                Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out,
                {
                    Size = window.FullSize,
                    BackgroundTransparency = 0.5,
                }
            )
            motionTween(
                main,
                Motion.Window,
                Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out,
                {Size = window.FullSize}
            )

            task.delay(Motion.Window + 0.03, function()
                if generation ~= window.WindowAnimationGeneration or window.Minimized then
                    return
                end

                window.WindowAnimating = false
                window:ClampToViewport(
                    window.ResolvedLayout == "Phone" and 6 or 8,
                    "Expanded"
                )
            end)
        end
    end)

    -- Dynamic key capture + hide/show handling.
    trackWindowConnection(UserInputService.InputBegan, function(input, processed)
        local capturingWindow = SharedUIState.CapturingWindow

        if capturingWindow then
            -- Only the window that owns the active capture consumes the key.
            if capturingWindow ~= window then
                return
            end

            if input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end

            local control = SharedUIState.CapturingControl

            if input.KeyCode == Enum.KeyCode.Escape then
                SharedUIState.SuppressToggleUntil = os.clock() + 0.25
                SharedUIState.CapturingWindow = nil
                SharedUIState.CapturingControl = nil

                if control and control.CancelCapture then
                    control:CancelCapture()
                end
                return
            end

            if input.KeyCode ~= Enum.KeyCode.Unknown then
                local keyName = input.KeyCode.Name

                -- Prevent this same keypress being treated as the newly-set
                -- hide/show shortcut by another loaded PuckUI callback.
                SharedUIState.SuppressToggleUntil = os.clock() + 0.30
                SharedUIState.CapturingWindow = nil
                SharedUIState.CapturingControl = nil

                window:SetToggleKey(input.KeyCode)

                if control then
                    control:_SetKeyName(keyName)
                    safeCallback(control.Callback, keyName)
                end
            end

            return
        end

        if os.clock() < (SharedUIState.SuppressToggleUntil or 0) then
            return
        end

        if processed then
            return
        end

        if input.UserInputType == Enum.UserInputType.Keyboard
            and input.KeyCode == window.ToggleKeyCode then
            window:Toggle()
        end
    end)

    window:ApplyResponsiveLayout()

    -- Config autosave watches control values instead of requiring every game
    -- script to manually call Save after each callback.
    task.spawn(function()
        task.wait(1.0)

        if not config.Available or not config.Enabled then
            return
        end

        config.Ready = true
        config.LastFingerprint = window:_ConfigFingerprint()

        -- If Auto Save is enabled and the selected profile does not exist yet,
        -- create it from the script's current defaults/loaded state.
        if config.AutoSave and not FileAPI.IsFile(configFilePath(config.Selected)) then
            window:_WriteConfig(config.Selected, false)
        end

        while window.ScreenGui and window.ScreenGui.Parent do
            if config.AutoSave and not config.Applying then
                local fingerprint = window:_ConfigFingerprint()

                if fingerprint ~= ""
                    and fingerprint ~= config.LastFingerprint then
                    window:_WriteConfig(config.Selected, false)
                end
            end

            task.wait(0.5)
        end
    end)

    return window
end

return PuckUI
]===]

local RemoteService = {Busy = nil, Next = {}, Count = 0, Sequence = 0}
function RemoteService:Call(label, cooldown, args, callback, options)
    options = type(options) == "table" and options or {}
    if not Runtime.Running or self.Busy or os.clock() < (self.Next[label] or 0) then return false end
    local remote = path(RS, "Remotes", "CommF_")
    if not remote or not remote:IsA("RemoteFunction") then
        log("Error", "ReplicatedStorage.Remotes.CommF_ unavailable")
        return false
    end

    self.Sequence += 1
    local requestId = self.Sequence
    local token = Runtime.Generation
    local generationBound = options.GenerationBound
    if generationBound == nil then generationBound = label == "Quest" end
    local timeout = math.clamp(tonumber(options.Timeout) or 10, 4, 30)
    local completed = false

    self.Next[label] = os.clock() + cooldown
    self.Busy = {Label = label, Started = os.clock(), Id = requestId}
    self.Count += 1

    local function finish(ok, packed, timeoutMessage)
        if completed then return end
        completed = true
        if self.Busy and self.Busy.Id == requestId then self.Busy = nil end
        if not Runtime.Running then return end
        if not ok then log("Error", label .. ": " .. tostring(timeoutMessage or (packed and packed[2]) or "request failed")) end
        -- Quest callbacks are tied to a farm generation. Shop/gacha/stat callbacks are not:
        -- changing targets must never discard the result of an already-issued money purchase.
        if callback and (not generationBound or token == Runtime.Generation) then
            if packed then callback(ok, table.unpack(packed, 2, packed.n))
            else callback(false, timeoutMessage or "timeout") end
        end
    end

    task.delay(timeout, function()
        if completed or not Runtime.Running then return end
        finish(false, nil, "server response timed out after " .. tostring(timeout) .. "s")
    end)

    local started = worker("CommF:" .. tostring(requestId), function()
        if not Runtime.Running then
            finish(false, nil, "runtime stopped")
            return
        end
        if generationBound and token ~= Runtime.Generation then
            finish(false, nil, "request became stale")
            return
        end
        if label == "Stats" and not Config.AutoStats or label == "Aura" and not Config.AutoAura then
            finish(false, nil, "automation was disabled")
            return
        end
        local packed = table.pack(pcall(remote.InvokeServer, remote, table.unpack(args)))
        finish(packed[1], packed)
    end)

    if not started then
        if self.Busy and self.Busy.Id == requestId then self.Busy = nil end
        completed = true
        return false
    end
    return true
end
local function findModule(names)
    local direct = path(RS, table.unpack(names))
    if direct and direct:IsA("ModuleScript") then return direct end
    -- Live hierarchy can move while names stay stable. Search only ModuleScripts
    -- and score exact suffix matches rather than trusting one dump path forever.
    local wanted = names[#names]
    local best, bestScore
    for _, item in ipairs(RS:GetDescendants()) do
        if item:IsA("ModuleScript") and item.Name == wanted then
            local score = 1
            local cursor = item.Parent
            for i = #names - 1, 1, -1 do
                if cursor and cursor.Name == names[i] then score += 5; cursor = cursor.Parent else break end
            end
            if not bestScore or score > bestScore then best, bestScore = item, score end
        end
    end
    return best
end
local function loadModule(key, names)
    if Runtime.Modules[key] then return end
    local module = findModule(names)
    if not module then
        log("Module", "Not found: " .. key .. " (fallback may be used)")
        return
    end
    worker("Module:" .. key, function()
        local ok, result = pcall(require, module)
        if not Runtime.Running then return end
        if ok and type(result) == "table" then
            Runtime.Modules[key] = result
            if key == "LiveQuests" and QuestService then QuestService.Dirty = true end
            log("Module", "Loaded " .. key .. " from " .. module:GetFullName())
        else
            log("Module", "Require failed " .. key .. ": " .. tostring(result) .. " (fallback may be used)")
        end
    end)
end
-- Quest selection must never depend on executor permission to require game modules.
-- The fuller dump confirms ReplicatedStorage.Quests is the authoritative live database.
-- Keep this exact snapshot as a fail-safe, but asynchronously prefer the live module when require works.
Runtime.Modules.Quests = BUNDLED_QUESTS
Runtime.Modules.BundledQuests = BUNDLED_QUESTS

local WorldService = {Next = 0}
local function validSea(sea)
    return sea == "Sea1" or sea == "Sea2" or sea == "Sea3"
end
function WorldService:Apply(sea, source)
    if not validSea(sea) then return false end
    source = source or "Unknown"
    if sea ~= Runtime.Sea then
        release("Realm changed")
        Runtime.Sea = sea
        if QuestService then QuestService.Dirty = true end
        if EnemyService then EnemyService:ClearLocations() end
        log("World", sea .. " via " .. source)
    end
    Runtime.SeaSource = source
    return true
end
function WorldService:Refresh()
    -- The three main seas are separate Roblox places. Prefer PlaceId because it
    -- is synchronous, cannot yield, and remains valid even if the Realm module
    -- is still loading or its async API changes.
    local placeSea = SEA_BY_PLACE[game.PlaceId]
    if placeSea then
        self.Next = os.clock() + 10
        self:Apply(placeSea, "PlaceId")
        return
    end

    -- Fallback for future/unknown places.  Realm is optional rather than a hard
    -- gate for the known Blox Fruits sea place IDs. Pass the module as self as
    -- well; Lua ignores the extra argument when the function was declared with
    -- dot syntax, while colon-declared methods require it.
    if os.clock() < self.Next or Runtime.Workers.World then return end
    local realm = Runtime.Modules.Realm
    if not realm or type(realm.getCurrentSeaAsync) ~= "function" then
        self.Next = os.clock() + 2
        return
    end
    self.Next = os.clock() + 15
    worker("World", function()
        local ok, sea = pcall(realm.getCurrentSeaAsync, realm)
        if not Runtime.Running then return end
        if not ok then
            log("Error", "Realm detection failed: " .. tostring(sea))
            return
        end
        if not self:Apply(sea, "Realm") then
            log("Error", "Realm returned unsupported sea: " .. tostring(sea))
        end
    end)
end

-- The newer dump's current CombatUtil.RunHitDetection accepts ONLY these rig part names
-- for an ordinary M1 hit (plus M1HitRegistry tagged parts). HumanoidRootPart itself is not
-- in the accepted set. Targeting a real accepted body part fixes enemies whose HRP is a poor
-- proxy for their hittable geometry (Dark Master is the first live case that exposed this).
local COMBAT_HIT_PART_ORDER = {
    "ModelHitbox", "UpperTorso", "LowerTorso", "Head",
    "RightHand", "LeftHand", "RightLowerArm", "LeftLowerArm", "RightUpperArm", "LeftUpperArm",
    "RightFoot", "LeftFoot", "RightLowerLeg", "LeftLowerLeg", "RightUpperLeg", "LeftUpperLeg",
}
local COMBAT_HIT_PART_SET = {}
for _, name in ipairs(COMBAT_HIT_PART_ORDER) do COMBAT_HIT_PART_SET[name] = true end

-- Cache active NPC enemies only. Stored templates are locations, never attack targets.
EnemyService = {
    Models = {}, Blocked = {}, SpawnPoints = {}, Connections = {}, Folder = nil, Spawns = nil, NextBind = 0,
    DamageMeta = setmetatable({}, {__mode = "k"}), DamageNext = 0,
}
function EnemyService:Remember(name, position)
    name = normalize(name)
    if name == "" or not position then return end
    local list = self.SpawnPoints[name] or {}
    self.SpawnPoints[name] = list
    for _, p in ipairs(list) do if (p - position).Magnitude < 15 then return end end
    if #list < 32 then table.insert(list, position) end
end
function EnemyService:ClearLocations() self.SpawnPoints = {}; self.Blocked = {} end
function EnemyService:Observe(model)
    if not model:IsA("Model") then return end
    self.Models[model] = true
    self:Remember(model:GetAttribute("DisplayName") or model.Name, pos(model))
    local h = model:FindFirstChildOfClass("Humanoid")
    if h then
        local wounded = h.MaxHealth > 0 and h.Health < h.MaxHealth - 0.01
        self.DamageMeta[model] = self.DamageMeta[model] or {
            LastHealth = h.Health,
            OurAttackUntil = 0,
            OurDamageAt = 0,
            OtherDamageAt = wounded and os.clock() or 0,
            ClaimedByUs = false,
        }
    end
end
function EnemyService:Bind()
    if os.clock() < self.NextBind then return end
    self.NextBind = os.clock() + 2
    local folder = workspace:FindFirstChild("Enemies")
    local spawns = path(workspace, "_WorldOrigin", "EnemySpawns")
    if folder == self.Folder and spawns == self.Spawns then return end
    disconnectAll(self.Connections)
    self.Models, self.Folder, self.Spawns = {}, folder, spawns
    self.DamageMeta = setmetatable({}, {__mode = "k"})
    if folder then
        connect(folder.ChildAdded, function(m) self:Observe(m) end, self.Connections)
        connect(folder.ChildRemoved, function(m)
            self.Models[m] = nil; self.Blocked[m] = nil; self.DamageMeta[m] = nil
        end, self.Connections)
        for _, m in ipairs(folder:GetChildren()) do self:Observe(m) end
    end
    if spawns then
        local function remember(s) self:Remember(s:GetAttribute("DisplayName") or s.Name, pos(s)) end
        connect(spawns.ChildAdded, remember, self.Connections)
        for _, s in ipairs(spawns:GetChildren()) do remember(s) end
    end
end
function EnemyService:CombatPart(m)
    if not m then return nil end
    -- Prefer direct rig parts in the exact order used for stable targeting. ModelHitbox is
    -- intentionally first: the current game uses it as an explicit accepted M1 registry part.
    for _, name in ipairs(COMBAT_HIT_PART_ORDER) do
        local p = m:FindFirstChild(name)
        if p and p:IsA("BasePart") then return p end
    end
    -- Some newer NPC assemblies nest the registered hit part one model deeper.
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("BasePart") and COMBAT_HIT_PART_SET[d.Name] then return d end
    end
    return nil
end
function EnemyService:Parts(m)
    if not m or not self.Folder or m.Parent ~= self.Folder then return nil end
    local h = m:FindFirstChildOfClass("Humanoid")
    local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
    if not h or h.Health <= 0 or not r or not r:IsA("BasePart") then return nil end
    return h, r, self:CombatPart(m) or r
end
function EnemyService:Matches(m, target)
    target = normalize(target)
    return normalize(m.Name) == target or normalize(m:GetAttribute("DisplayName")) == target
end
function EnemyService:MarkOurAttack(model, linger)
    if not model then return end
    local h = model:FindFirstChildOfClass("Humanoid")
    local meta = self.DamageMeta[model]
    if not meta then
        meta = {LastHealth = h and h.Health or nil, OurAttackUntil = 0, OurDamageAt = 0, OtherDamageAt = 0, ClaimedByUs = false}
        self.DamageMeta[model] = meta
    end
    meta.OurAttackUntil = math.max(meta.OurAttackUntil or 0, os.clock() + (tonumber(linger) or 1.4))
end
function EnemyService:UpdateDamageOwnership()
    local now = os.clock()
    if now < self.DamageNext then return end
    self.DamageNext = now + 0.15
    for model in pairs(self.Models) do
        local h = model:FindFirstChildOfClass("Humanoid")
        if h then
            local meta = self.DamageMeta[model]
            if not meta then
                local wounded = h.MaxHealth > 0 and h.Health < h.MaxHealth - 0.01
                meta = {LastHealth = h.Health, OurAttackUntil = 0, OurDamageAt = 0, OtherDamageAt = wounded and now or 0, ClaimedByUs = false}
                self.DamageMeta[model] = meta
            elseif meta.LastHealth and h.Health < meta.LastHealth - 0.001 then
                if now <= (meta.OurAttackUntil or 0) then
                    meta.OurDamageAt = now
                    meta.ClaimedByUs = true
                else
                    meta.OtherDamageAt = now
                end
            end
            meta.LastHealth = h.Health
        end
    end
end
function EnemyService:IsOurs(model)
    local meta = model and self.DamageMeta[model]
    return meta ~= nil and meta.ClaimedByUs == true
end
function EnemyService:IsContested(model)
    if not Config.AvoidContested or not model then return false end
    local meta = self.DamageMeta[model]
    if not meta or meta.ClaimedByUs then return false end
    return (meta.OtherDamageAt or 0) > 0 and os.clock() - meta.OtherDamageAt <= Config.ContestedSeconds
end
function EnemyService:Select(name, origin)
    self:UpdateDamageOwnership()
    local best, bestScore
    for m in pairs(self.Models) do
        local h, r = self:Parts(m)
        local blocked = self.Blocked[m]
        if blocked and blocked <= os.clock() then self.Blocked[m] = nil; blocked = nil end
        if h and not blocked and self:Matches(m, name) and (not self:IsContested(m) or self:IsOurs(m)) then
            local distance = (r.Position - origin).Magnitude
            local score = distance + math.abs(r.Position.Y - origin.Y) * 0.15
            if m == Runtime.Target then score = score - 35 end
            if self:IsOurs(m) then score = score - 10000 end
            if not bestScore or score < bestScore then best, bestScore = m, score end
        end
    end
    return best
end
function EnemyService:NearestSpawn(name, origin)
    name = normalize(name)
    local candidates = self.SpawnPoints[name] or {}
    local best, distance
    for _, p in ipairs(candidates) do
        local d = (p - origin).Magnitude
        if not distance or d < distance then best, distance = p, d end
    end
    if not best and Runtime.Sea == "Sea1" then
        for _, a in ipairs(GameData.sea1Spawns[name] or {}) do
            local p = vec(a); local d = (p - origin).Magnitude
            if not distance or d < distance then best, distance = p, d end
        end
    end
    return best
end
function EnemyService:Destroy()
    disconnectAll(self.Connections)
    self.Models = {}; self.Blocked = {}; self.SpawnPoints = {}; self.DamageMeta = setmetatable({}, {__mode = "k"})
end

QuestService = {Records = {}, ByKey = {}, Dirty = true, NextBuild = 0, Failures = {}, PendingUntil = 0, LastSignature = nil}
function QuestService:NPCName(id)
    local guide = Runtime.Modules.Guide
    if guide and guide.Data and type(guide.Data.NPCList) == "table" then
        for _, data in pairs(guide.Data.NPCList) do
            if type(data) == "table" and data.InternalQuestName == id and data.NPCName then return data.NPCName end
        end
    end
    return GameData.npcNames[id]
end
function QuestService:RefreshNPCIndex()
    local now = os.clock()
    if now < (self.NPCIndexNext or 0) or Runtime.Workers.QuestNPCIndex then return end
    self.NPCIndexNext = now + 5
    worker("QuestNPCIndex", function()
        local index = {}
        for _, folder in ipairs({workspace:FindFirstChild("NPCs") or false, RS:FindFirstChild("NPCs") or false}) do
            if folder then
                for n, npc in ipairs(folder:GetDescendants()) do
                    if not Runtime.Running then return end
                    if (npc:IsA("Model") or npc:IsA("BasePart")) and npc:GetAttribute("NPCReady") == true then
                        local position = pos(npc)
                        if position then
                            index[npc.Name] = index[npc.Name] or {}
                            table.insert(index[npc.Name], position)
                        end
                    end
                    if n % 200 == 0 then task.wait() end
                end
            end
        end
        self.NPCIndex = index
    end)
end
function QuestService:Position(id, origin)
    local best, distance
    local function consider(p)
        if typeof(p) ~= "Vector3" then return end
        local d = (p - origin).Magnitude
        if not distance or d < distance then best, distance = p, d end
    end
    local guide = Runtime.Modules.Guide
    if guide and guide.Data and type(guide.Data.NPCList) == "table" then
        for _, data in pairs(guide.Data.NPCList) do
            if type(data) == "table" and data.InternalQuestName == id then consider(data.Position) end
        end
    end
    if best then return best end
    local npcName = self:NPCName(id)
    if npcName then
        self:RefreshNPCIndex()
        for _, position in ipairs(self.NPCIndex and self.NPCIndex[npcName] or {}) do consider(position) end
    end
    if not best and Runtime.Sea == "Sea1" then
        for _, p in ipairs(GameData.sea1NPCPositions[id] or {}) do consider(vec(p)) end
    end
    return best
end
function QuestService:Build()
    if not self.Dirty and os.clock() < self.NextBuild then return end
    self.NextBuild, self.Dirty = os.clock() + 10, false
    self.Records, self.ByKey = {}, {}
    local database = Runtime.Modules.LiveQuests or Runtime.Modules.Quests
    if not database then return end
    for id, stages in pairs(database) do
        -- Auto Level intentionally stays on the known main progression quest IDs. The live
        -- Quests module also contains side chains (Citizen/Bartilo/etc.) that must not outrank
        -- ordinary level farming merely because their LevelReq is high.
        if GameData.npcNames[id] and type(stages) == "table" then
            local minimum = math.huge
            for _, data in pairs(stages) do
                if type(data) == "table" and type(data.LevelReq) == "number" then minimum = math.min(minimum, data.LevelReq) end
            end
            -- Progression bands are inferred from this dump; locations must ALSO resolve in the current realm.
            local sea = minimum >= 1500 and "Sea3" or minimum >= 700 and "Sea2" or "Sea1"
            if sea == Runtime.Sea then
                for index, data in pairs(stages) do
                    if type(index) == "number" and type(data) == "table" and type(data.LevelReq) == "number" and type(data.Task) == "table" and not data.CustomTasks and not data.Job then
                        local target, count = next(data.Task)
                        if type(target) == "string" and type(count) == "number" and count > 0 and next(data.Task, target) == nil then
                            local record = {Id = id, Index = index, Key = id .. ":" .. index, Level = data.LevelReq,
                                Target = target, Count = count, Boss = count == 1, Name = data.Name, Sea = sea}
                            table.insert(self.Records, record); self.ByKey[record.Key] = record
                        end
                    end
                end
            end
        end
    end
    table.sort(self.Records, function(a, b)
        if a.Level ~= b.Level then return a.Level > b.Level end
        return a.Key < b.Key
    end)
end
function QuestService:SyncActive(force)
    local now = os.clock()
    if not force and (Runtime.ActiveQuestKnown or now < (Runtime.QuestSyncAt or 0)) then return end
    if Runtime.Workers.QuestStateSync then return end
    Runtime.QuestSyncAt = now + 5
    local net = path(RS, "Modules", "Net")
    local rf = net and net:FindFirstChild("RF/GuideDataUpdate")
    if not rf or not rf:IsA("RemoteFunction") then
        -- We still learn state from Remotes.QuestUpdate after StartQuest/AbandonQuest.
        log("Quest", "GuideDataUpdate RF unavailable; waiting for QuestUpdate event")
        return
    end
    worker("QuestStateSync", function()
        local ok, result = pcall(rf.InvokeServer, rf, "GetGuideData")
        if not Runtime.Running then return end
        if ok and type(result) == "table" then
            Runtime.ActiveQuest = result.QuestData
            Runtime.ActiveQuestKnown = true
            log("Quest", "Initial quest state synchronized directly")
        else
            log("Quest", "Initial quest sync failed: " .. tostring(result))
        end
    end)
end
function QuestService:Active()
    if not Runtime.ActiveQuestKnown then
        local guideData = Runtime.Modules.GuideData
        if guideData and type(guideData.Data) == "table" then
            Runtime.ActiveQuest = guideData.Data.QuestData
            Runtime.ActiveQuestKnown = true
        else
            self:SyncActive(false)
        end
    end
    return Runtime.ActiveQuest, Runtime.ActiveQuestKnown
end
function QuestService:Matches(active, q)
    if type(active) ~= "table" or not q then return false end
    if active.InternalQuestName ~= q.Id then return false end
    local info = active.Info
    if type(info) ~= "table" or type(info.Task) ~= "table" then return false end
    return info.Task[q.Target] == q.Count and (not info.Name or info.Name == q.Name)
end
function QuestService:Choose(level, origin, bossName)
    local team = Player.Team and Player.Team.Name
    local nearest, nearestDistance, bestLevel
    for _, q in ipairs(self.Records) do
        local suitable = q.Level <= level and (bossName and q.Boss and (bossName == "Auto available" or q.Target == bossName) or not bossName and not q.Boss)
        if q.Id == "MarineQuest" and team ~= "Marines" then suitable = false end
        if q.Id == "BanditQuest1" and team == "Marines" then suitable = false end
        local failure = self.Failures[q.Key]
        if failure and os.clock() < failure.Until then suitable = false end
        if suitable then
            local p = self:Position(q.Id, origin)
            if p and (not bossName or bossName ~= "Auto available" or EnemyService:Select(q.Target, origin)) then
                local d = (p - origin).Magnitude
                if not bestLevel or q.Level > bestLevel or q.Level == bestLevel and d < nearestDistance then
                    nearest, nearestDistance, bestLevel = q, d, q.Level
                end
            end
        end
    end
    return nearest
end
function QuestService:Reject(q, reason)
    local old = self.Failures[q.Key]
    local attempts = (old and old.Count or 0) + 1
    self.Failures[q.Key] = {Count = attempts, Until = os.clock() + math.min(120, 8 * 2 ^ math.min(attempts, 4))}
    log("Quest", q.Key .. ": " .. reason)
    self.PendingUntil = 0
    release(reason)
end

Movement = {Connection = nil, Goal = nil, Owner = nil, Saved = {}, Failures = 0, Error = nil, EffectiveMode = nil, CombatTween = nil, CombatTweenGoal = nil, NextCombatTween = 0}
function Movement:Restore()
    for part, saved in pairs(self.Saved) do
        if part.Parent then
            if part:IsA("Humanoid") then part.AutoRotate = saved else part.CanCollide = saved end
        end
    end
    self.Saved = {}
end
function Movement:ApplyCombatFacing()
    -- CombatController binds CombatFocusAdjust at Input priority and flattens pitch.
    -- Only enforce a held enemy stance, never quest travel, idle, or another owner.
    if not Runtime.Running or not self.Goal or not self.Hold or Runtime.Owner ~= self.Owner
        or not Runtime.Target or self.RequestKey ~= Runtime.Target then return end
    local _, humanoid, root = char()
    if not root then return end
    if self.Saved[humanoid] == nil then self.Saved[humanoid] = humanoid.AutoRotate end
    humanoid.AutoRotate = false
    root.CFrame = CFrame.new(root.Position) * self.Goal.Rotation
    root.AssemblyAngularVelocity = Vector3.zero
end
function Movement:BindCombatFacing()
    if self.FacingBound then return end
    self.FacingBound = true
    RunService:BindToRenderStep("PuckAFK_BF_CombatFacing", Enum.RenderPriority.Last.Value + 1, function()
        self:ApplyCombatFacing()
    end)
    self.FacingPhysics = RunService.PreSimulation:Connect(function()
        self:ApplyCombatFacing()
    end)
end
function Movement:Cancel(reason)
    if self.FacingBound then
        RunService:UnbindFromRenderStep("PuckAFK_BF_CombatFacing")
        self.FacingBound = nil
    end
    if self.FacingPhysics then self.FacingPhysics:Disconnect(); self.FacingPhysics = nil end
    if self.CombatTween then pcall(self.CombatTween.Cancel, self.CombatTween); self.CombatTween = nil end
    self.CombatTweenGoal, self.NextCombatTween = nil, 0
    if self.Connection then self.Connection:Disconnect(); self.Connection = nil end
    local _, h, r = char()
    if self.Goal and r then
        r.AssemblyLinearVelocity = Vector3.zero
        if h then h:Move(Vector3.zero); h:MoveTo(r.Position) end
    end
    self.Goal, self.Owner, self.RequestKey, self.EffectiveMode = nil, nil, nil, nil
    self:Restore()
end
function Movement:GoTo(owner, goal, tolerance, hold, requestKey)
    if not Runtime.Running or Runtime.Owner ~= owner then return false end
    local c, _, r = char()
    if not c then return false end
    if typeof(goal) ~= "CFrame" then return false end
    if self.Owner ~= owner or not self.Goal or self.RequestKey ~= requestKey then
        self:Cancel("New request")
        self.Owner = owner; self.RequestKey = requestKey; self.Started = os.clock(); self.CheckAt = os.clock()
        self.CheckPosition = r.Position; self.Best = (r.Position - goal.Position).Magnitude
        self.Error = nil
    end
    self.Goal, self.Tolerance, self.Hold = goal, tolerance or 3, hold == true
    self.Arrived = (r.Position - goal.Position).Magnitude <= self.Tolerance
    if Runtime.Target and requestKey == Runtime.Target and self.Hold then self:BindCombatFacing() end
    if self.Connection then return self.Arrived end
    self.Connection = RunService.Heartbeat:Connect(function(dt)
        local character, humanoid, root = char()
        if not Runtime.Running or not character or not self.Goal or Runtime.Owner ~= self.Owner then self:Cancel("Invalid owner/character"); return end
        local delta = self.Goal.Position - root.Position
        local distance = delta.Magnitude
        self.Arrived = distance <= self.Tolerance
        if self.Arrived then self.Started = os.clock() end
        if self.Saved[humanoid] == nil then self.Saved[humanoid] = humanoid.AutoRotate end
        local farmOwner = self.Owner == "Level" or self.Owner == "Boss" or self.Owner == "Enemy"
        local verticalFarm = farmOwner and (Config.Position == "Above" or Config.Position == "Below" or Config.Position == "Orbit" or math.abs(tonumber(Config.Height) or 0) > 3)
        local movementMode = Config.Movement == "Walk" and verticalFarm and "Smooth" or Config.Movement
        self.EffectiveMode = movementMode

        -- Auto Dodge owns translation for a few tenths of a second. The old system only
        -- changed Movement.Goal, so the normal follow could immediately counter-steer and
        -- make the dodge look like an animation with almost no actual displacement.
        -- StepMotion writes the HRP position itself for the burst, then hands control back
        -- to the normal exact-position follow so Above/Behind/etc. smoothly recover.
        local dodgeMoved = DodgeService and DodgeService:IsDodging() and DodgeService:StepMotion(root, humanoid, dt)
        if not dodgeMoved then
            if movementMode == "Walk" then
                if os.clock() >= (self.NextWalk or 0) then humanoid:MoveTo(self.Goal.Position); self.NextWalk = os.clock() + 0.4 end
            else
                humanoid.AutoRotate = false
                if Config.NoCollision then
                    for _, part in ipairs(character:GetChildren()) do
                        if part:IsA("BasePart") then
                            if self.Saved[part] == nil then self.Saved[part] = part.CanCollide end
                            part.CanCollide = false
                        end
                    end
                end
                -- Long travel remains speed-limited. Near a locked enemy, use a bounded
                -- exponential follow instead of repeatedly restarting TweenService on the HRP.
                -- This continuously tracks a moving enemy without accumulating position error
                -- or fighting the face-down render-step rotation.
                local combatHold = farmOwner and self.Hold and Runtime.Target ~= nil and self.RequestKey == Runtime.Target
                local useCombatFollow = combatHold and distance <= 30
                if useCombatFollow then
                    if self.CombatTween then pcall(self.CombatTween.Cancel, self.CombatTween); self.CombatTween = nil end
                    self.CombatTweenGoal = self.Goal
                    local speed = math.max(25, tonumber(Config.Speed) or 100)
                    local safeDt = math.clamp(dt, 0, 0.05)
                    local alpha = 1 - math.exp(-12 * safeDt)
                    local eased = delta * alpha
                    local maxStep = speed * safeDt
                    if eased.Magnitude > maxStep and eased.Magnitude > 0 then
                        eased = eased.Unit * maxStep
                    end
                    local nextPosition = distance > 0.02 and (root.Position + eased) or self.Goal.Position
                    root.CFrame = CFrame.new(nextPosition) * self.Goal.Rotation
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                else
                    if self.CombatTween then pcall(self.CombatTween.Cancel, self.CombatTween); self.CombatTween = nil end
                    self.CombatTweenGoal = nil
                    local speed = math.max(1, tonumber(Config.Speed) or 100)
                    local step = math.min(distance, speed * math.min(dt, 0.1))
                    local nextPosition = distance > 0.01 and root.Position + delta.Unit * step or root.Position
                    root.CFrame = CFrame.new(nextPosition) * self.Goal.Rotation
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                end
            end
        end
        if os.clock() - self.CheckAt >= 5 then
            local progress = (root.Position - self.CheckPosition).Magnitude
            if not self.Arrived and progress < 3 then
                self.Error = "Movement stalled"
                self:Cancel(self.Error)
                return
            end
            self.CheckAt, self.CheckPosition = os.clock(), root.Position
        end
        -- Timeout grows with initial route length and survives refreshes to the same request.
        local timeout = math.max(25, self.Best / math.max(12, movementMode == "Walk" and humanoid.WalkSpeed or Config.Speed) * 3 + 12)
        if not self.Arrived and os.clock() - self.Started > timeout then self.Error = "Movement timed out"; self:Cancel(self.Error); return end
        if self.Arrived and not self.Hold then self:Cancel("Arrived") end
    end)
    return self.Arrived
end
function Movement:Position(targetRoot, weaponData)
    local d = math.max(0.5, tonumber(Config.Distance) or 3)
    local height = tonumber(Config.Height) or 0
    local side = tonumber(Config.Side) or 0
    local mode = Config.Position or "Behind"

    -- Positioning stays independent from the proven M1 path. Distance is the primary
    -- offset for the selected mode; Height/Side remain additive and use world-up Y.

    -- Exact-position mode: never rewrite the user-selected offset for melee reach.
    -- The configured Distance/Height/Side values now remain authoritative.

    -- Use a yaw-only enemy basis and absolute world Y. HumanoidRootPart pitch/roll can
    -- change slightly during combat/physics; transforming Above through the full target
    -- CFrame can therefore turn a fixed vertical offset into a moving one and cause drift.
    local targetPosition = targetRoot.Position
    local forward = Vector3.new(targetRoot.CFrame.LookVector.X, 0, targetRoot.CFrame.LookVector.Z)
    if forward.Magnitude < 0.05 then forward = Vector3.new(0, 0, -1) else forward = forward.Unit end
    local right = Vector3.new(targetRoot.CFrame.RightVector.X, 0, targetRoot.CFrame.RightVector.Z)
    if right.Magnitude < 0.05 then right = Vector3.new(1, 0, 0) else right = right.Unit end

    local destination
    if mode == "Above" then
        destination = targetPosition + right * side + Vector3.new(0, d + height, 0)
    elseif mode == "Below" then
        destination = targetPosition + right * side + Vector3.new(0, -d + height, 0)
    elseif mode == "Front" then
        destination = targetPosition + forward * d + right * side + Vector3.new(0, height, 0)
    elseif mode == "Side" then
        destination = targetPosition + right * (d + side) + Vector3.new(0, height, 0)
    elseif mode == "Orbit" then
        local radius = math.max(0.5, tonumber(Config.OrbitRadius) or d)
        local angle = (os.clock() - Runtime.Started) * math.rad(tonumber(Config.OrbitSpeed) or 35)
        destination = targetPosition
            + right * (math.cos(angle) * radius + side)
            - forward * (math.sin(angle) * radius)
            + Vector3.new(0, height, 0)
    else -- Behind / Custom Offset
        destination = targetPosition - forward * d + right * side + Vector3.new(0, height, 0)
    end
    if (destination - targetPosition).Magnitude < 0.75 then
        destination = targetPosition - forward * 1.5
    end

    if mode == "Above" and Config.AboveLookDown then
        -- This is intentionally a custom farming stance, not Roblox's literal Shift Lock.
        -- Shift Lock normally yaws the character only; here we pitch the whole character
        -- down so the legs trail behind/up instead of hanging directly inside the NPC's
        -- normal melee reach. A controlled angle is used rather than a 90-degree dive so
        -- Dark Step's leg-based M1 overlap can still reach the target.
        local pitch = math.rad(math.clamp(tonumber(Config.AboveLookDownAngle) or 45, 0, 75))
        local flatToTarget = Vector3.new(targetRoot.Position.X - destination.X, 0, targetRoot.Position.Z - destination.Z)
        local heading
        if flatToTarget.Magnitude > 0.05 then
            heading = flatToTarget.Unit
        else
            local fallback = Vector3.new(-targetRoot.CFrame.LookVector.X, 0, -targetRoot.CFrame.LookVector.Z)
            heading = fallback.Magnitude > 0.05 and fallback.Unit or Vector3.new(0, 0, -1)
        end
        local lookDirection = heading * math.cos(pitch) + Vector3.new(0, -math.sin(pitch), 0)
        Runtime.PositionStatus = "Above · face-down " .. tostring(math.floor(math.deg(pitch) + 0.5)) .. "°"
        return CFrame.lookAt(destination, destination + lookDirection, Vector3.yAxis)
    end

    -- Other modes remain upright and face horizontally toward the target.
    local flatAim = Vector3.new(targetRoot.Position.X, destination.Y, targetRoot.Position.Z)
    if (flatAim - destination).Magnitude < 0.05 then
        flatAim = destination + targetRoot.CFrame.LookVector
    end
    Runtime.PositionStatus = tostring(mode) .. " · upright"
    return CFrame.lookAt(destination, flatAim)
end

-- Predictive defensive movement. Threat detection still watches the locked NPC's
-- attack-like animations, but the actual dodge is now an independent physical burst.
-- Normal combat follow is temporarily prevented from counter-steering the character,
-- so the avatar visibly leaves the attack line and then smoothly returns to its selected
-- Above/Behind/etc. offset after the burst.
DodgeService = {
    Target = nil, AnimationConnection = nil, Animator = nil,
    DodgeStartedAt = 0, DodgeUntil = 0, BurstUntil = 0, CooldownUntil = 0,
    Side = 1, DodgeStart = nil, DodgeGoal = nil, DodgeDistance = 0,
    LastPlayerHumanoid = nil, LastPlayerHealth = nil, Reason = "Watching",
}
local DODGE_RANGE, DODGE_DURATION, DODGE_BURST_TIME, DODGE_COOLDOWN = 12, 0.46, 0.24, 0.72
local DODGE_SIDE_DISTANCE, DODGE_AWAY_DISTANCE = 8.0, 3.0
local DODGE_ATTACK_WORDS = {
    "attack", "basic", "slash", "swing", "punch", "kick", "strike",
    "smash", "slam", "skill", "melee", "combo", "cast", "charge",
}
local DODGE_REACTION_WORDS = {
    "hurt", "stun", "damage", "damaged", "death", "die", "knock", "fall", "hitreact",
}
function DodgeService:DisconnectTarget()
    if self.AnimationConnection then self.AnimationConnection:Disconnect(); self.AnimationConnection = nil end
    self.Target, self.Animator = nil, nil
end
function DodgeService:Clear(status)
    self:DisconnectTarget()
    self.DodgeStartedAt, self.DodgeUntil, self.BurstUntil, self.CooldownUntil = 0, 0, 0, 0
    self.DodgeStart, self.DodgeGoal, self.DodgeDistance = nil, nil, 0
    self.LastPlayerHumanoid, self.LastPlayerHealth = nil, nil
    self.Reason = status or "Watching"
    Runtime.DodgeStatus = self.Reason
end
function DodgeService:Destroy()
    self:Clear("Stopped")
end
function DodgeService:IsDodging()
    return Config.AutoDodge == true and self.DodgeGoal ~= nil and os.clock() < (self.DodgeUntil or 0)
end
function DodgeService:IsReactionTrack(track)
    local text = string.lower(tostring(track and track.Name or ""))
    local animation = track and track.Animation
    if animation then text = text .. " " .. string.lower(tostring(animation.Name or "")) end
    for _, word in ipairs(DODGE_REACTION_WORDS) do
        if string.find(text, word, 1, true) then return true end
    end
    return false
end
function DodgeService:IsThreatTrack(track, targetRoot)
    if not track or self:IsReactionTrack(track) then return false end
    local text = string.lower(tostring(track.Name or ""))
    local animation = track.Animation
    if animation then text = text .. " " .. string.lower(tostring(animation.Name or "")) end
    for _, word in ipairs(DODGE_ATTACK_WORDS) do
        if string.find(text, word, 1, true) then return true end
    end
    -- Many NPC attack clips have generic names. Action-priority, non-looped, short clips
    -- are treated as a wind-up only while the NPC is facing our nearby character.
    local actionPriority = track.Priority == Enum.AnimationPriority.Action
        or track.Priority == Enum.AnimationPriority.Action2
        or track.Priority == Enum.AnimationPriority.Action3
        or track.Priority == Enum.AnimationPriority.Action4
    if not actionPriority or track.Looped then return false end
    local length = tonumber(track.Length) or 0
    if length > 3.25 then return false end
    local _, _, ourRoot = char()
    if not ourRoot or not targetRoot then return false end
    local offset = ourRoot.Position - targetRoot.Position
    local flat = Vector3.new(offset.X, 0, offset.Z)
    if flat.Magnitude <= 2.5 then return true end
    local forward = Vector3.new(targetRoot.CFrame.LookVector.X, 0, targetRoot.CFrame.LookVector.Z)
    if forward.Magnitude < 0.05 then return true end
    return forward.Unit:Dot(flat.Unit) > 0.1
end
function DodgeService:BuildGoal(ourRoot, targetRoot)
    if not ourRoot or not targetRoot then return nil end
    local targetPosition = targetRoot.Position
    local forward = Vector3.new(targetRoot.CFrame.LookVector.X, 0, targetRoot.CFrame.LookVector.Z)
    if forward.Magnitude < 0.05 then forward = Vector3.new(0, 0, -1) else forward = forward.Unit end
    local right = Vector3.new(targetRoot.CFrame.RightVector.X, 0, targetRoot.CFrame.RightVector.Z)
    if right.Magnitude < 0.05 then right = Vector3.new(1, 0, 0) else right = right.Unit end

    -- When Above is selected our horizontal offset can be almost zero. In that case use
    -- the opposite of the enemy's facing direction as the away component. Keep current Y
    -- exactly so repeated dodges can never accumulate vertical drift.
    local away = Vector3.new(ourRoot.Position.X - targetPosition.X, 0, ourRoot.Position.Z - targetPosition.Z)
    if away.Magnitude < 0.2 then away = -forward else away = away.Unit end
    local lateral = right * (self.Side * DODGE_SIDE_DISTANCE)
    local outward = away * DODGE_AWAY_DISTANCE
    local flatDelta = lateral + outward
    if flatDelta.Magnitude < 0.5 then flatDelta = right * (self.Side * DODGE_SIDE_DISTANCE) end
    return ourRoot.Position + Vector3.new(flatDelta.X, 0, flatDelta.Z)
end
function DodgeService:Trigger(reason)
    if not Config.AutoDodge or os.clock() < self.CooldownUntil or not Runtime.Target then return false end
    local _, _, ourRoot = char()
    local targetHumanoid, targetRoot = EnemyService:Parts(Runtime.Target)
    if not ourRoot or not targetHumanoid or not targetRoot or targetHumanoid.Health <= 0 then return false end
    if (ourRoot.Position - targetRoot.Position).Magnitude > DODGE_RANGE then return false end

    local now = os.clock()
    self.Side = -self.Side
    local goal = self:BuildGoal(ourRoot, targetRoot)
    if not goal then return false end
    self.DodgeStart = ourRoot.Position
    self.DodgeGoal = goal
    self.DodgeDistance = (goal - ourRoot.Position).Magnitude
    self.DodgeStartedAt = now
    self.BurstUntil = now + DODGE_BURST_TIME
    self.DodgeUntil = now + DODGE_DURATION
    self.CooldownUntil = now + DODGE_COOLDOWN
    self.Reason = reason or "attack wind-up"
    Runtime.DodgeStatus = string.format("Dodging %.1f studs · %s", self.DodgeDistance, self.Reason)

    -- Cancel any residual Humanoid MoveTo steering. Movement's Heartbeat remains bound,
    -- but while IsDodging() is true it delegates translation to StepMotion below.
    local _, humanoid = char()
    if humanoid then
        pcall(humanoid.Move, humanoid, Vector3.zero)
        pcall(humanoid.MoveTo, humanoid, ourRoot.Position)
    end
    return true
end
function DodgeService:StepMotion(root, humanoid, dt)
    if not self:IsDodging() or not root or not self.DodgeStart or not self.DodgeGoal then return false end
    local now = os.clock()
    local elapsed = math.max(0, now - self.DodgeStartedAt)
    local burst = math.max(0.08, DODGE_BURST_TIME)
    local t = math.clamp(elapsed / burst, 0, 1)
    -- Fast cubic ease-out: most of the displacement happens immediately during the
    -- enemy wind-up instead of slowly drifting sideways after the hit already lands.
    local eased = 1 - (1 - t) ^ 3
    local desired = self.DodgeStart:Lerp(self.DodgeGoal, eased)

    -- Use a generous bounded step so low configured farm speed cannot reduce an 8-stud
    -- dodge to a barely visible twitch. This is still smooth rather than a teleport.
    local safeDt = math.clamp(tonumber(dt) or 0, 0, 0.05)
    local burstSpeed = math.max(72, (tonumber(Config.Speed) or 100) * 1.35)
    local delta = desired - root.Position
    local maxStep = burstSpeed * safeDt
    if delta.Magnitude > maxStep and maxStep > 0 then desired = root.Position + delta.Unit * maxStep end

    local rotation = root.CFrame.Rotation
    if Movement and Movement.Goal then rotation = Movement.Goal.Rotation end
    root.CFrame = CFrame.new(desired) * rotation
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    if humanoid then
        humanoid.AutoRotate = false
        humanoid:Move(Vector3.zero)
    end

    local moved = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(self.DodgeStart.X, 0, self.DodgeStart.Z)).Magnitude
    Runtime.DodgeStatus = string.format("Dodging %.1f/%.1f studs · %s", moved, self.DodgeDistance, self.Reason)
    return true
end
function DodgeService:BindTarget(target, targetHumanoid, targetRoot)
    if self.Target == target and self.AnimationConnection then return end
    self:DisconnectTarget()
    self.Target = target
    if not target or not targetHumanoid then return end
    local animator = targetHumanoid:FindFirstChildOfClass("Animator")
    if not animator then return end
    self.Animator = animator
    self.AnimationConnection = animator.AnimationPlayed:Connect(function(track)
        if not Runtime.Running or Runtime.Target ~= target or not Config.AutoDodge then return end
        task.defer(function()
            if Runtime.Running and Runtime.Target == target and self:IsThreatTrack(track, targetRoot) then
                self:Trigger("attack wind-up")
            end
        end)
    end)
end
function DodgeService:Observe(target, targetHumanoid, targetRoot)
    if not Config.AutoDodge then
        if self.Target then self:DisconnectTarget() end
        self.DodgeStart, self.DodgeGoal = nil, nil
        Runtime.DodgeStatus = "Off"
        return
    end
    self:BindTarget(target, targetHumanoid, targetRoot)
    local _, ourHumanoid = char()
    if ourHumanoid ~= self.LastPlayerHumanoid then
        self.LastPlayerHumanoid = ourHumanoid
        self.LastPlayerHealth = ourHumanoid and ourHumanoid.Health or nil
    elseif ourHumanoid then
        local health = ourHumanoid.Health
        if self.LastPlayerHealth and health < self.LastPlayerHealth - 0.05 and target then
            self:Trigger("damage follow-up")
        end
        self.LastPlayerHealth = health
    end
    if os.clock() >= self.DodgeUntil and self.DodgeGoal then
        self.DodgeStart, self.DodgeGoal, self.DodgeDistance = nil, nil, 0
        Runtime.DodgeStatus = "Watching"
    elseif not target then
        Runtime.DodgeStatus = "Watching"
    end
end
function DodgeService:Apply(baseGoal, targetRoot)
    -- Keep the selected combat offset as Movement.Goal even during a dodge. The dedicated
    -- StepMotion layer moves the root away while preventing normal follow from cancelling
    -- the burst, then normal movement naturally brings us back to this exact base goal.
    return baseGoal
end

local WeaponService = {List = {}, Dirty = true, NextRefresh = 0, SwitchedAt = 0, Original = nil}
local function guessedWeaponType(tool)
    local explicit = tool:GetAttribute("WeaponType") or tool:GetAttribute("ToolType") or tool:GetAttribute("ItemType")
    if type(explicit) == "string" then
        local low = string.lower(explicit)
        if low:find("melee") or low:find("fighting") then return "Melee" end
        if low:find("sword") then return "Sword" end
        if low:find("gun") then return "Gun" end
        if low:find("fruit") then return "Demon Fruit" end
    end
    local low = string.lower(tool.Name)
    if low == "combat" or low:find("karate") or low:find("kung") or low:find("claw") or low:find("step") or low:find("talon") or low:find("human") or low:find("art") then return "Melee" end
    if low:find("fruit") then return "Demon Fruit" end
    -- Unknown tools stay usable in Auto/Equipped/name modes instead of being discarded.
    return "Unknown"
end
function WeaponService:Refresh()
    if not self.Dirty and os.clock() < self.NextRefresh then return end
    self.Dirty, self.NextRefresh, self.List = false, os.clock() + 2, {}
    local util = Runtime.Modules.CombatUtil
    for _, folder in ipairs({Player.Character or false, Player:FindFirstChildOfClass("Backpack") or false}) do
        if folder then
            for _, tool in ipairs(folder:GetChildren()) do
                if tool:IsA("Tool") then
                    local data, native = nil, false
                    if util then
                        local ok, result = pcall(function()
                            return util:GetWeaponData(util:GetWeaponName(tool))
                        end)
                        if ok and type(result) == "table" then data, native = result, true end
                    end
                    if not data then
                        data = {WeaponType = guessedWeaponType(tool), HitboxMagnitude = 7, Moduleless = true}
                    end
                    -- Do not block the farm merely because metadata is inaccessible.
                    table.insert(self.List, {Tool = tool, Data = data, Native = native})
                end
            end
        end
    end
    table.sort(self.List, function(a, b) return a.Tool.Name < b.Tool.Name end)
end
function WeaponService:Choose(finishing)
    local wanted = finishing and Config.MasteryWeapon or Config.Weapon
    local mode = finishing and "Auto" or Config.WeaponMode
    if mode == "Fruit" then mode = "Demon Fruit" end
    local best, bestScore
    for _, entry in ipairs(self.List) do
        local tool, data = entry.Tool, entry.Data
        local typeMatch = mode == "Auto" or mode == "Equipped" and tool.Parent == Player.Character or data.WeaponType == mode
        if data.WeaponType == "Unknown" and mode ~= "Auto" and mode ~= "Equipped" then typeMatch = false end
        if tool.Parent and (wanted == "Auto" or wanted == tool.Name) and typeMatch then
            local score = data.WeaponType == "Melee" and 100 or data.WeaponType == "Sword" and 80 or data.WeaponType == "Demon Fruit" and 60 or data.WeaponType == "Gun" and 40 or 20
            if tool.Parent == Player.Character then score += 10 end
            if entry.Native then score += 3 end
            if not bestScore or score > bestScore then best, bestScore = entry, score end
        end
    end
    return best
end
function WeaponService:Equip(entry)
    local c, h = char()
    if not c or not entry or not entry.Tool or not entry.Tool.Parent then return false end
    if entry.Tool.Parent ~= c then
        if not self.Original then self.Original = c:FindFirstChildOfClass("Tool") or false end
        Combat:Stop()
        h:EquipTool(entry.Tool); self.SwitchedAt = os.clock()
        return false
    end
    if os.clock() - self.SwitchedAt < 0.35 then return false end
    local util = Runtime.Modules.CombatUtil
    if entry.Native and util and entry.Data.WeaponType ~= "Melee" then
        local equipped = c:FindFirstChild("EquippedWeapon")
        local ok, matches = pcall(function()
            return equipped and util:GetPureWeaponName(util:GetWeaponName(equipped)) == util:GetPureWeaponName(util:GetWeaponName(entry.Tool))
        end)
        if ok and not matches then return false end
    end
    return true
end
Combat = {Entry = nil, LastAttack = 0, LastM1Attack = 0, Camera = nil, CameraFrame = nil, CameraBound = nil, AimPart = nil, BlockedUntil = 0,
    SwingUntil = 0, WatchTarget = nil, WatchTool = nil, WatchHealth = nil,
    NoDamageAt = 0, InputRetry = false, ComboCount = 0, ComboPendingSkill = false}

function Combat:Observe(target, humanoid, entry)
    local now = os.clock()
    if self.WatchTarget ~= target or self.WatchTool ~= entry.Tool then
        self.WatchTarget, self.WatchTool = target, entry.Tool
        self.WatchHealth, self.NoDamageAt = humanoid.Health, now
        self.InputRetry, self.SwingUntil = false, 0
        self.ComboCount, self.ComboPendingSkill = 0, false
    elseif humanoid.Health < (self.WatchHealth or humanoid.Health) then
        self.NoDamageAt = now
    end
    self.WatchHealth = humanoid.Health
    local _, _, root = char()
    local enemyRoot = target and target:FindFirstChild("HumanoidRootPart")
    if root and enemyRoot and (root.Position - enemyRoot.Position).Magnitude > 6 then
        self.NoDamageAt = now
        return
    end
    if now - self.NoDamageAt >= 4 then self.InputRetry = true end
end

function Combat:SwingDuration(entry)
    -- Reserve the native basic animation, including the delayed overlap check.
    local duration = 0.75
    local _, humanoid = char()
    local util = Runtime.Modules.CombatUtil
    if humanoid and util and type(util.GetLoadedAnimsFor) == "function" then
        pcall(function()
            local name = util:GetWeaponName(entry.Tool)
            for key, track in pairs(util:GetLoadedAnimsFor(name, humanoid)) do
                if tostring(key):match("^basic") then
                    local speed = (track:GetAttribute("SpeedMult") or 1)
                        * (humanoid.Parent:GetAttribute("AttackSpeedMultiplier") or 1)
                    duration = math.max(duration, track.Length / math.max(0.1, speed) + 0.12)
                end
            end
        end)
    end
    return math.clamp(duration, 0.75, 3)
end

function Combat:SetCameraTarget(targetPart)
    self.AimPart = targetPart
    if not Config.CameraAim or not targetPart or not targetPart.Parent then
        Runtime.CameraStatus = Config.CameraAim and "Idle" or "Off"
        if self.CameraBound then
            RunService:UnbindFromRenderStep("PuckAFK_BF_CameraLock")
            self.CameraBound = nil
        end
        return
    end
    if self.CameraBound then return end
    self.CameraBound = true
    RunService:BindToRenderStep("PuckAFK_BF_CameraLock", Enum.RenderPriority.Camera.Value + 1, function()
        local part = self.AimPart
        if not Runtime.Running or not Config.CameraAim or not Runtime.Target or not part or not part.Parent then return end
        local camera = workspace.CurrentCamera
        if not camera then return end
        if self.Camera ~= camera then
            self.Camera = camera
            self.CameraFrame = camera.CFrame
        end
        local delta = part.Position - camera.CFrame.Position
        if delta.Magnitude > 0.05 then
            camera.CFrame = CFrame.lookAt(camera.CFrame.Position, part.Position)
        end
        Runtime.CameraStatus = "Locked to " .. tostring(part.Name)
    end)
end

function Combat:Stop()
    if self.Entry and self.Entry.Tool.Parent then pcall(self.Entry.Tool.Deactivate, self.Entry.Tool) end
    self.Entry = nil
    self.SwingUntil = 0
    self.ComboCount, self.ComboPendingSkill = 0, false
    self.AimPart = nil
    if self.CameraBound then
        RunService:UnbindFromRenderStep("PuckAFK_BF_CameraLock")
        self.CameraBound = nil
    end
    if self.Camera and self.Camera == workspace.CurrentCamera and self.CameraFrame then self.Camera.CFrame = self.CameraFrame end
    self.Camera, self.CameraFrame = nil, nil
    Runtime.CameraStatus = "Idle"
end

function Combat:Attack(entry, targetRoot, aimPart)
    if Runtime.NPCInteracting then return false end
    local c, _, r = char()
    if not c or not entry or not entry.Tool or entry.Tool.Parent ~= c or not targetRoot then return false end

    local now = os.clock()
    local weaponType = entry.Data and entry.Data.WeaponType or "Unknown"
    if now < self.BlockedUntil or now - self.LastAttack < Config.AttackInterval then return false end
    if weaponType ~= "Melee" and now < self.SwingUntil then return false end

    local distance = (r.Position - targetRoot.Position).Magnitude
    local lockedOn = Runtime.Target ~= nil and Movement.RequestKey == Runtime.Target and Movement.Hold == true
    local nearLocked = lockedOn and distance <= 12
    if weaponType == "Gun" then
        if distance > 150 then return false end
    elseif not nearLocked and distance > 8 then
        return false
    end

    if UIS:GetFocusedTextBox() or GuiService.MenuIsOpen then return false end
    if CombatSkillService and now < CombatSkillService.BusyUntil then
        Runtime.M1Status = "Waiting for skill to finish"
        return false
    end

    local targetPart = aimPart or targetRoot
    self:SetCameraTarget(targetPart)

    -- When Auto Level is movement-locked to a nearby enemy, use the same real Mouse1
    -- input route as the user's manual click.  This prevents a successful native call
    -- from suppressing the click even though the actual basic attack did not start.
    local forceMouse1 = weaponType == "Melee" and nearLocked

    local controller, util = Runtime.Modules.Combat, Runtime.Modules.CombatUtil
    if weaponType == "Melee" and not forceMouse1 and not self.InputRetry and entry.Native and controller and type(controller.Attack) == "function" then
        if util and type(util.CanAttack) == "function" then
            local checked, allowed = pcall(util.CanAttack, util, c, weaponType)
            if checked and not allowed then
                Runtime.M1Status = "Waiting for stun/busy/cooldown"
                return false
            end
        end
        self.Entry, self.LastAttack = entry, now
        local ok, err = pcall(controller.Attack, controller, entry.Tool)
        if ok then
            self.LastM1Attack = os.clock()
            self.SwingUntil = os.clock() + self:SwingDuration(entry)
            Runtime.CombatPath = "Native melee M1"
            Runtime.M1Status = "M1 requested · native"
            EnemyService:MarkOurAttack(Runtime.Target, 1.4)
            return true
        end
        Runtime.LastError = "Native M1: " .. tostring(err)
    end

    self.Entry = entry
    self.LastAttack = now
    Runtime.CombatPath = forceMouse1 and "Locked nearby · real Mouse1" or "Simple M1 input"
    Runtime.M1Status = forceMouse1 and string.format("Clicking M1 · locked %.1f studs", distance) or "Clicking M1"
    if EnemyService then EnemyService:MarkOurAttack(Runtime.Target, weaponType == "Gun" and 2.0 or 1.4) end

    local camera = workspace.CurrentCamera
    local x, y = 400, 300
    if camera then
        x, y = math.floor(camera.ViewportSize.X * 0.5), math.floor(camera.ViewportSize.Y * 0.5)
    end
    if weaponType == "Gun" and camera then
        local p = camera:WorldToViewportPoint(targetPart.Position)
        if p.Z > 0 then x, y = math.floor(p.X), math.floor(p.Y) end
    end

    -- Pick an input point that the UI will not consume. Camera locking is independent
    -- from this point; the camera itself remains forced onto the enemy every frame.
    if weaponType ~= "Gun" and camera then
        local size = camera.ViewportSize
        local projected = camera:WorldToViewportPoint(targetPart.Position)
        local candidates = {Vector2.new(projected.X, projected.Y),
            Vector2.new(size.X * 0.8, size.Y * 0.45),
            Vector2.new(size.X * 0.5, size.Y * 0.4),
            Vector2.new(size.X * 0.8, size.Y * 0.7)}
        local pg = Player:FindFirstChildOfClass("PlayerGui")
        for _, point in ipairs(candidates) do
            local blocked = point.X < 20 or point.Y < 60 or point.X > size.X - 20 or point.Y > size.Y - 20
            for _, guiRoot in ipairs({pg or false, game:GetService("CoreGui")}) do
                if guiRoot and not blocked then
                    pcall(function()
                        for _, object in ipairs(guiRoot:GetGuiObjectsAtPosition(point.X, point.Y)) do
                            if object:IsA("GuiButton") or object:IsA("TextBox") or object.Active then
                                blocked = true
                                break
                            end
                        end
                    end)
                end
            end
            if not blocked then x, y = math.floor(point.X), math.floor(point.Y); break end
        end
    end

    local fired = false
    local okVIM, vim = pcall(game.GetService, game, "VirtualInputManager")
    if okVIM and vim then
        fired = pcall(function()
            vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.03)
            vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
    end
    if not fired and type(mouse1click) == "function" then fired = pcall(mouse1click) end
    if not fired then fired = pcall(entry.Tool.Activate, entry.Tool) end

    if not fired then
        self.BlockedUntil = os.clock() + 1
        Runtime.CombatPath = "M1 input unavailable"
        Runtime.M1Status = "Executor could not send M1"
        return false
    end

    self.LastM1Attack = os.clock()
    -- Melee Mouse1 must remain free to continue its natural click chain.
    if weaponType ~= "Melee" and weaponType ~= "Gun" then self.SwingUntil = os.clock() + self:SwingDuration(entry) end
    return true
end

CombatSkillService = {
    Next = 0, Cursor = 0, BusyUntil = 0, LastCastAt = 0, NextByKey = {}, LegacyCache = setmetatable({}, {__mode = "k"}),
    LegacyRetry = setmetatable({}, {__mode = "k"}),
    KeyOrder = {"Z", "X", "C", "V", "F"},
    KeyCodes = {Z = Enum.KeyCode.Z, X = Enum.KeyCode.X, C = Enum.KeyCode.C, V = Enum.KeyCode.V, F = Enum.KeyCode.F},
    VirtualKeys = {Z = 0x5A, X = 0x58, C = 0x43, V = 0x56, F = 0x46},
}
function CombatSkillService:Mastery(tool)
    local attr = tool:GetAttribute("Level")
    if type(attr) == "number" then return attr end
    local level = tool:FindFirstChild("Level")
    if level and level:IsA("ValueBase") and type(level.Value) == "number" then return level.Value end
    return 0
end
function CombatSkillService:SkillFrame(tool, key)
    local pg = Player:FindFirstChildOfClass("PlayerGui")
    local main = pg and pg:FindFirstChild("Main")
    local skills = main and main:FindFirstChild("Skills")
    local set = skills and skills:FindFirstChild(tool.Name)
    return set and set:FindFirstChild(key)
end
function CombatSkillService:LegacyData(tool)
    local cached = self.LegacyCache[tool]
    if cached ~= nil then
        if cached ~= false then return cached end
        if os.clock() < (self.LegacyRetry[tool] or 0) then return nil end
        self.LegacyCache[tool] = nil
    end
    local pg = Player:FindFirstChildOfClass("PlayerGui")
    local root = pg and pg:FindFirstChild("MovesetModules")
    local folder = root and root:FindFirstChild(tool.Name)
    local module = folder and folder:FindFirstChild("LegacyDataAggregate")
    local data
    if module and module:IsA("ModuleScript") then
        local ok, result = pcall(require, module)
        if ok and type(result) == "table" then data = result end
    end
    self.LegacyCache[tool] = data or false
    if not data then self.LegacyRetry[tool] = os.clock() + 3 else self.LegacyRetry[tool] = nil end
    return data
end
function CombatSkillService:Requirement(tool, key)
    local frame = self:SkillFrame(tool, key)
    if frame then
        local level = frame:FindFirstChild("Level")
        local text = level and level:IsA("TextLabel") and level.Text or ""
        local req = tonumber(string.match(text, "(%d+)%s*$") or string.match(text, "(%d+)"))
        if req then return req, frame end
    end
    local data = self:LegacyData(tool)
    local req = data and type(data.Lvl) == "table" and tonumber(data.Lvl[key]) or nil
    return req, frame
end
function CombatSkillService:IsReady(tool, key)
    if Config["Skill" .. key] ~= true then return false end
    local requirement, frame = self:Requirement(tool, key)
    if requirement == nil then return false end
    if self:Mastery(tool) < requirement then return false end
    if os.clock() < (self.NextByKey[key] or 0) then return false end
    if frame then
        local cooldown = frame:FindFirstChild("Cooldown")
        if cooldown and cooldown:IsA("GuiObject") then
            local width = math.abs(cooldown.Size.X.Scale) + math.abs(cooldown.Size.X.Offset) / math.max(1, frame.AbsoluteSize.X)
            if width > 0.08 then return false end
        end
    end
    return true
end
function CombatSkillService:SendKey(key, down)
    local code = self.KeyCodes[key]
    local ok = false
    local vim
    pcall(function() vim = game:GetService("VirtualInputManager") end)
    if vim and code then
        ok = pcall(vim.SendKeyEvent, vim, down, code, false, game)
    end
    if not ok then
        local fn = down and (rawget(Env, "keypress") or rawget(_G, "keypress")) or (rawget(Env, "keyrelease") or rawget(_G, "keyrelease"))
        if type(fn) == "function" then ok = pcall(fn, self.VirtualKeys[key]) end
    end
    return ok
end
function CombatSkillService:Aim(targetRoot)
    if not Config.SkillAim then return nil end
    local camera = workspace.CurrentCamera
    if not camera then return nil end
    local old = camera.CFrame
    camera.CFrame = CFrame.lookAt(camera.CFrame.Position, targetRoot.Position)
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        local size = camera.ViewportSize
        vim:SendMouseMoveEvent(size.X * 0.5, size.Y * 0.5, game)
    end)
    return {Camera = camera, CFrame = old}
end
function CombatSkillService:RestoreAim(record)
    if record and record.Camera and record.Camera == workspace.CurrentCamera and record.Camera.Parent then
        record.Camera.CFrame = record.CFrame
    end
end
function CombatSkillService:Step(entry, targetRoot)
    if Runtime.NPCInteracting then return false end
    if not Config.AutoSkills or not entry or not entry.Tool or entry.Tool.Parent ~= Player.Character then return false end
    local _, _, root = char()
    if not root or not targetRoot or (root.Position - targetRoot.Position).Magnitude > Config.SkillMaxRange then return false end
    local now = os.clock()
    if now < self.BusyUntil then return true end
    if UIS:GetFocusedTextBox() or GuiService.MenuIsOpen then return false end
    local character = Player.Character
    local busy = character and character:FindFirstChild("Busy")
    local stun = character and character:FindFirstChild("Stun")
    if (busy and busy.Value) or (stun and stun.Value > 0) then return true end
    if Combat and now < Combat.SwingUntil then return false end
    if now < self.Next then return false end
    self.Next = now + 0.12
    for offset = 1, #self.KeyOrder do
        local index = (self.Cursor + offset - 1) % #self.KeyOrder + 1
        local key = self.KeyOrder[index]
        if self:IsReady(entry.Tool, key) then
            self.Cursor = index
            self.NextByKey[key] = now + 2.0 -- UI cooldown is authoritative when available; this is only an anti-spam floor.
            self.BusyUntil = now + math.max(0.2, Config.SkillHold + 0.15)
            self.LastCastAt = now
            if EnemyService then EnemyService:MarkOurAttack(Runtime.Target, 3.5) end
            worker("CombatSkill", function()
                local aim = self:Aim(targetRoot)
                local pressed = self:SendKey(key, true)
                if pressed then
                    task.wait(math.clamp(Config.SkillHold, 0.05, 1.5))
                    self:SendKey(key, false)
                else
                    log("Error", "Skill input unavailable; executor cannot synthesize Z/X/C/V/F")
                    Config.AutoSkills = false
                    if Runtime.Controls and Runtime.Controls.AutoSkills then Runtime.Controls.AutoSkills:Set(false) end
                end
                task.wait(0.05)
                self:RestoreAim(aim)
            end)
            return true
        end
    end
    return false
end

local StatService = {Next = 0, Cursor = 0, Disabled = {}}
function StatService:Step()
    if not Config.AutoStats or os.clock() < self.Next or RemoteService.Busy then return end
    self.Next = os.clock() + 1.5
    local data = Player:FindFirstChild("Data")
    local points = value(data, "Points", 0)
    if type(points) ~= "number" or points <= 0 then return end
    local stats = data and data:FindFirstChild("Stats")
    local choices = {}
    for _, pair in ipairs({{"Melee","StatMelee"},{"Defense","StatDefense"},{"Sword","StatSword"},{"Gun","StatGun"},{"Demon Fruit","StatFruit"}}) do
        local node = stats and stats:FindFirstChild(pair[1])
        local current = value(node, "Level", nil)
        if Config[pair[2]] and type(current) == "number" and os.clock() >= (self.Disabled[pair[1]] or 0) then
            table.insert(choices, {Name = pair[1], Level = current})
        end
    end
    if #choices == 0 then return end
    local choice
    if Config.StatDistribution == "Round robin" then self.Cursor = self.Cursor % #choices + 1; choice = choices[self.Cursor]
    else table.sort(choices, function(a,b) if a.Level == b.Level then return a.Name < b.Name end; return a.Level < b.Level end); choice = choices[1] end
    RemoteService:Call("Stats", 1.5, {"AddPoint", choice.Name, math.min(points, Config.StatBatch)}, function(ok, result)
        if not ok then self.Disabled[choice.Name] = os.clock() + 30; return end
        -- Acknowledgement values differ; replicated Points/Stats are authoritative.
        worker("StatCheck", function()
            task.wait(2)
            if not Runtime.Running then return end
            local nowData = Player:FindFirstChild("Data")
            local nowLevel = value(path(nowData, "Stats", choice.Name), "Level", nil)
            if nowLevel == choice.Level then self.Disabled[choice.Name] = os.clock() + 60; log("Stats", choice.Name .. " did not increase; paused for 60 seconds") end
        end)
    end)
end
local AuraService = {Next = 0}
function AuraService:Step()
    if not Config.AutoAura or os.clock() < self.Next or RemoteService.Busy then return end
    local c = char()
    if not c or not Tags:HasTag(c, "Buso") or c:FindFirstChild("HasBuso") then return end
    self.Next = os.clock() + 12
    RemoteService:Call("Aura", 12, {"Buso"})
end


-- ============================================================================
-- Population, privacy and purchasing services (client dump build 4617)
-- ============================================================================
local function beli()
    return tonumber(value(Player and Player:FindFirstChild("Data"), "Beli", 0)) or 0
end

local function findRemoteFunction(name)
    local remotes = RS:FindFirstChild("Remotes")
    local direct = remotes and remotes:FindFirstChild(name, true)
    if direct and direct:IsA("RemoteFunction") then return direct end
    local anywhere = RS:FindFirstChild(name, true)
    return anywhere and anywhere:IsA("RemoteFunction") and anywhere or nil
end

local function prettyFruitName(name)
    local raw = tostring(name or "")
    for split = 2, #raw - 1 do
        if raw:sub(split, split) == "-" then
            local left, right = raw:sub(1, split - 1), raw:sub(split + 1)
            if left == right then return left end
        end
    end
    return raw:gsub("%-", " ")
end

PrivacyService = {Humanoids = setmetatable({}, {__mode = "k"}), PlayerListKnown = false, PlayerListOriginal = true}
function PrivacyService:CaptureHumanoid(h)
    if not h or self.Humanoids[h] then return end
    local saved = {}
    pcall(function() saved.DisplayDistanceType = h.DisplayDistanceType end)
    pcall(function() saved.NameDisplayDistance = h.NameDisplayDistance end)
    pcall(function() saved.HealthDisplayDistance = h.HealthDisplayDistance end)
    self.Humanoids[h] = saved
end
function PrivacyService:ApplyNameplate()
    local c = Player and Player.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    if not h then return end
    self:CaptureHumanoid(h)
    local saved = self.Humanoids[h]
    if Config.HideOwnNameplate then
        pcall(function() h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end)
        pcall(function() h.NameDisplayDistance = 0 end)
        pcall(function() h.HealthDisplayDistance = 0 end)
    elseif saved then
        if saved.DisplayDistanceType ~= nil then pcall(function() h.DisplayDistanceType = saved.DisplayDistanceType end) end
        if saved.NameDisplayDistance ~= nil then pcall(function() h.NameDisplayDistance = saved.NameDisplayDistance end) end
        if saved.HealthDisplayDistance ~= nil then pcall(function() h.HealthDisplayDistance = saved.HealthDisplayDistance end) end
    end
end
function PrivacyService:ApplyPlayerList()
    if not self.PlayerListKnown then
        local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList)
        if ok then self.PlayerListOriginal, self.PlayerListKnown = enabled, true end
    end
    local enabled = self.PlayerListKnown and self.PlayerListOriginal or true
    if Config.HidePlayerList then enabled = false end
    pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, enabled)
end
function PrivacyService:Step() self:ApplyNameplate(); self:ApplyPlayerList() end
function PrivacyService:Restore()
    for h, saved in pairs(self.Humanoids) do
        if h and h.Parent then
            if saved.DisplayDistanceType ~= nil then pcall(function() h.DisplayDistanceType = saved.DisplayDistanceType end) end
            if saved.NameDisplayDistance ~= nil then pcall(function() h.NameDisplayDistance = saved.NameDisplayDistance end) end
            if saved.HealthDisplayDistance ~= nil then pcall(function() h.HealthDisplayDistance = saved.HealthDisplayDistance end) end
        end
    end
    if self.PlayerListKnown then pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, self.PlayerListOriginal) end
end

local function executorHttpGet(url)
    local req
    if type(request) == "function" then req = request
    elseif type(http_request) == "function" then req = http_request
    elseif type(syn) == "table" and type(syn.request) == "function" then req = syn.request end
    if req then
        local ok, response = pcall(req, {Url = url, Method = "GET", Headers = {Accept = "application/json"}})
        if ok and type(response) == "table" then
            local body = response.Body or response.body
            local code = tonumber(response.StatusCode or response.Status or response.status_code) or 200
            if code >= 200 and code < 300 and type(body) == "string" then return body end
            return nil, "HTTP " .. tostring(code)
        elseif not ok then return nil, tostring(response) end
    end
    local ok, body = pcall(game.HttpGet, game, url)
    if ok and type(body) == "string" then return body end
    return nil, tostring(body or "HTTP requests are unavailable in this executor")
end

ServerService = {Next = 0, Searching = false, Visited = {[game.JobId] = true}, LastOtherCount = 0, Friend = nil}
function ServerService:QueueSelf()
    local source = Env.__PUCKAFK_BLOXFRUITS_SELF_SOURCE
    if type(source) ~= "string" or source == "" then return false, "self source is not available" end
    local queue
    if type(queue_on_teleport) == "function" then queue = queue_on_teleport
    elseif type(queueonteleport) == "function" then queue = queueonteleport
    elseif type(syn) == "table" and type(syn.queue_on_teleport) == "function" then queue = syn.queue_on_teleport end
    if not queue then return false, "queue-on-teleport is not supported by this executor" end
    local quoted = string.format("%q", source)
    local payload = "local s=" .. quoted .. "; local e=_G; if type(getgenv)=='function' then local ok,v=pcall(getgenv); if ok and type(v)=='table' then e=v end end; e.__PUCKAFK_BLOXFRUITS_SELF_SOURCE=s; local f,err=loadstring(s,'PuckAFK_BloxFruits'); if not f then error(err) end; f()"
    local ok, err = pcall(queue, payload)
    return ok, err
end
function ServerService:ConfiguredFriend()
    local needle = string.lower(tostring(Config.ExemptFriend or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if needle ~= "" then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= Player and (string.lower(p.Name) == needle or string.lower(p.DisplayName) == needle or tostring(p.UserId) == needle) then return p end
        end
        return nil
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= Player then
            local ok, isFriend = pcall(Player.IsFriendsWith, Player, p.UserId)
            if ok and isFriend then return p end
        end
    end
end
function ServerService:OtherCount()
    local friend = self:ConfiguredFriend()
    self.Friend = friend
    local count = math.max(0, #Players:GetPlayers() - 1 - (friend and 1 or 0))
    self.LastOtherCount = count
    return count, friend
end
function ServerService:FindAndHop(force)
    if self.Searching or Runtime.Workers.ServerSearch then return false end
    local others, friend = self:OtherCount()
    if not force and others <= Config.MaxOtherPlayers then
        Runtime.ServerStatus = string.format("%d other players%s · within limit %d", others, friend and (" · exempt " .. friend.Name) or "", Config.MaxOtherPlayers)
        return false
    end
    self.Searching = true
    Runtime.ServerStatus = "Searching public servers…"
    worker("ServerSearch", function()
        local candidates, cursor = {}, nil
        local target = math.max(0, math.floor(tonumber(Config.MaxOtherPlayers) or 9))
        for _ = 1, 4 do
            local url = "https://games.roblox.com/v1/games/" .. tostring(game.PlaceId) .. "/servers/Public?sortOrder=Asc&limit=100"
            if cursor and cursor ~= "" then url = url .. "&cursor=" .. HttpService:UrlEncode(cursor) end
            local body, httpErr = executorHttpGet(url)
            if not body then Runtime.ServerStatus = "Server search unavailable: " .. tostring(httpErr); log("Server", Runtime.ServerStatus); break end
            local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
            if not ok or type(decoded) ~= "table" then Runtime.ServerStatus = "Roblox server response could not be decoded"; break end
            for _, server in ipairs(decoded.data or {}) do
                local id, playing, maxPlayers = tostring(server.id or ""), tonumber(server.playing), tonumber(server.maxPlayers)
                if id ~= "" and id ~= game.JobId and playing and maxPlayers and playing < maxPlayers and playing <= target and not self.Visited[id] then
                    table.insert(candidates, {Id = id, Playing = playing, Max = maxPlayers})
                end
            end
            cursor = decoded.nextPageCursor
            if #candidates > 0 or not cursor or cursor == "" then break end
        end
        table.sort(candidates, function(a, b) if a.Playing == b.Playing then return a.Id < b.Id end return a.Playing < b.Playing end)
        local chosen = candidates[1]
        self.Searching = false
        if not Runtime.Running then return end
        if not chosen then Runtime.ServerStatus = "No public server at or below " .. target .. " players found yet"; return end
        self.Visited[chosen.Id] = true
        Runtime.Counters.ServerHops += 1
        Runtime.ServerStatus = "Joining server with " .. chosen.Playing .. " current players…"
        local queued, queueErr = self:QueueSelf()
        if not queued then Runtime.ServerStatus = Runtime.ServerStatus .. " · auto-resume unavailable"; log("Server", tostring(queueErr)) end
        state("SERVER_HOP", Runtime.ServerStatus)
        if Movement then Movement:Cancel("Server hop") end
        if Combat then Combat:Stop() end
        local ok, err = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, game.PlaceId, chosen.Id, Player)
        if not ok then Runtime.ServerStatus = "Server hop failed: " .. tostring(err); log("Error", Runtime.ServerStatus) end
    end)
    return true
end
function ServerService:Step()
    if os.clock() < self.Next then return end
    self.Next = os.clock() + 20
    local others, friend = self:OtherCount()
    Runtime.ServerStatus = string.format("%d other players%s · limit %d", others, friend and (" · exempt " .. friend.Name) or "", Config.MaxOtherPlayers)
    if Config.AutoSmallServer and others > Config.MaxOtherPlayers then self:FindAndHop(false) end
end


-- Physical fruits in the supplied dump are Tools with OriginalName/ItemId attributes.
-- Player-dropped fruits additionally carry DroppedBy / DroppedByUserId, so this service
-- deliberately ignores those and only chases map-spawned physical fruits.
FruitPickupService = {
    Items = setmetatable({}, {__mode = "k"}), Connections = {}, Current = nil, Started = 0,
    PendingStore = nil, StoreNext = 0, Bound = false, Blocked = setmetatable({}, {__mode = "k"}),
    ExistingScanDone = false, ExistingScanBusy = false,
}
function FruitPickupService:IsFruit(tool)
    if not tool or not tool:IsA("Tool") then return false end
    if tool.ToolTip == "Blox Fruit" or string.find(string.lower(tool.Name), "fruit", 1, true) ~= nil then return true end
    if tool:FindFirstChild("EatRemote", true) then return true end
    local original = tool:GetAttribute("OriginalName")
    if type(original) == "string" and original ~= "" then
        local left, right = string.match(original, "^(.+)%-(.+)$")
        if left and right and string.lower(left) == string.lower(right) then return true end
    end
    return false
end
function FruitPickupService:IsPlayerDropped(tool)
    local id = tool:GetAttribute("DroppedByUserId")
    local name = tool:GetAttribute("DroppedBy")
    return id ~= nil or type(name) == "string" and name ~= ""
end
function FruitPickupService:IsWorldFruit(tool)
    return self:IsFruit(tool) and tool:IsDescendantOf(workspace) and not self:IsPlayerDropped(tool)
end
function FruitPickupService:Observe(instance)
    if instance:IsA("Tool") and self:IsWorldFruit(instance) then self.Items[instance] = true end
end
function FruitPickupService:ScanExisting()
    if self.ExistingScanDone or self.ExistingScanBusy or not Runtime.Running then return end
    self.ExistingScanBusy = true
    worker("FruitExistingScan", function()
        local descendants = workspace:GetDescendants()
        for index, instance in ipairs(descendants) do
            if not Runtime.Running then break end
            if instance:IsA("Tool") then self:Observe(instance) end
            if index % 500 == 0 then task.wait() end
        end
        self.ExistingScanDone, self.ExistingScanBusy = true, false
    end)
end
function FruitPickupService:Bind()
    if not self.Bound then
        self.Bound = true
        connect(workspace.ChildAdded, function(child) self:Observe(child) end, self.Connections)
        connect(workspace.DescendantAdded, function(child) if child:IsA("Tool") then self:Observe(child) end end, self.Connections)
        for _, child in ipairs(workspace:GetChildren()) do self:Observe(child) end
    end
    if Config.AutoCollectSpawnedFruits then self:ScanExisting() end
end
function FruitPickupService:Handle(tool)
    if not tool then return nil end
    local h = tool:FindFirstChild("Handle")
    if h and h:IsA("BasePart") then return h end
    return tool:FindFirstChildWhichIsA("BasePart", true)
end
function FruitPickupService:HasWork()
    if self.PendingStore and self.PendingStore.Parent then return true end
    for tool in pairs(self.Items) do
        local untilAt = self.Blocked[tool]
        if untilAt and untilAt <= os.clock() then self.Blocked[tool] = nil; untilAt = nil end
        if not untilAt and self:IsWorldFruit(tool) and self:Handle(tool) then return true end
    end
    return false
end
function FruitPickupService:Select(origin)
    local best, score
    for tool in pairs(self.Items) do
        local untilAt = self.Blocked[tool]
        if untilAt and untilAt <= os.clock() then self.Blocked[tool] = nil; untilAt = nil end
        if not untilAt and self:IsWorldFruit(tool) then
            local handle = self:Handle(tool)
            if handle then
                local d = (handle.Position - origin).Magnitude
                if not score or d < score then best, score = tool, d end
            end
        else
            if not tool.Parent or not tool:IsDescendantOf(workspace) then self.Items[tool] = nil end
        end
    end
    return best
end
function FruitPickupService:Store(tool)
    if not Config.AutoStoreSpawnedFruits or not tool or not tool.Parent then return false end
    if os.clock() < self.StoreNext or RemoteService.Busy then self.PendingStore = tool; return true end
    local c, h = char()
    local backpack = Player:FindFirstChildOfClass("Backpack")
    if not c or not h or not (tool.Parent == c or tool.Parent == backpack) then self.PendingStore = nil; return false end
    if tool.Parent ~= c then h:EquipTool(tool); WeaponService.Dirty = true; self.PendingStore = tool; self.StoreNext = os.clock() + 0.6; return true end
    local original = tool:GetAttribute("OriginalName")
    if type(original) ~= "string" or original == "" then self.PendingStore = nil; return false end
    self.StoreNext = os.clock() + 2
    return RemoteService:Call("StoreSpawnedFruit", 2, {"StoreFruit", original, tool}, function(ok, result)
        if ok and result == true then
            Runtime.FruitPickupStatus = "Stored " .. tool.Name
        elseif typeof(result) == "number" then
            Runtime.FruitPickupStatus = "Picked up " .. tool.Name .. " · storage full (capacity " .. tostring(result) .. ")"
        else
            Runtime.FruitPickupStatus = "Picked up " .. tool.Name .. " · could not auto-store"
        end
        self.PendingStore = nil
        WeaponService.Dirty = true
    end)
end
function FruitPickupService:Step(owner)
    if not Config.AutoCollectSpawnedFruits then self.Current = nil; return false end
    self:Bind()
    if self.PendingStore and self.PendingStore.Parent then
        Runtime.FruitPickupStatus = "Storing " .. self.PendingStore.Name .. "…"
        self:Store(self.PendingStore)
        return true
    end
    -- Never abandon an enemy/boss after this script has actually landed damage on it.
    if Runtime.Target and EnemyService and EnemyService:IsOurs(Runtime.Target) and EnemyService:Parts(Runtime.Target) then
        Runtime.FruitPickupStatus = "Fruit waiting · finishing engaged " .. normalize(Runtime.Target.Name)
        return false
    end
    local _, _, root = char()
    if not root then return false end
    local tool = self.Current
    if not tool or not self:IsWorldFruit(tool) then
        tool = self:Select(root.Position)
        self.Current, self.Started = tool, os.clock()
    end
    if not tool then Runtime.FruitPickupStatus = "No natural fruit detected"; return false end
    local handle = self:Handle(tool)
    if not handle then self.Blocked[tool] = os.clock() + 15; self.Current = nil; return false end
    Runtime.FruitPickupStatus = "Collecting " .. tool.Name .. " · " .. math.floor((root.Position - handle.Position).Magnitude) .. " studs"
    state("COLLECT_FRUIT", tool.Name)
    local distance = (root.Position - handle.Position).Magnitude
    Movement:GoTo(owner, CFrame.new(handle.Position + Vector3.new(0, 1.5, 0)), 2.5, true, "Fruit:" .. tostring(tool))
    if distance <= 6 then
        if type(firetouchinterest) == "function" then
            pcall(firetouchinterest, root, handle, 0); pcall(firetouchinterest, root, handle, 1)
        end
    end
    local backpack = Player:FindFirstChildOfClass("Backpack")
    if tool.Parent == backpack or tool.Parent == Player.Character then
        Movement:Cancel("Fruit collected")
        self.Items[tool] = nil; self.Current = nil
        Runtime.Counters.FruitsCollected += 1
        Runtime.FruitPickupStatus = "Collected " .. tool.Name
        notify("Collected spawned fruit: " .. tool.Name)
        if Config.AutoStoreSpawnedFruits then self.PendingStore = tool; self:Store(tool) end
        return true
    end
    if os.clock() - self.Started > 25 then
        self.Blocked[tool] = os.clock() + 30; self.Current = nil; Movement:Cancel("Fruit pickup timed out")
        Runtime.FruitPickupStatus = "Could not reach " .. tool.Name .. " · retrying later"
    end
    return true
end
function FruitPickupService:Destroy()
    disconnectAll(self.Connections)
    self.Items = setmetatable({}, {__mode = "k"}); self.Blocked = setmetatable({}, {__mode = "k"}); self.Current = nil; self.PendingStore = nil; self.Bound = false
    self.ExistingScanDone, self.ExistingScanBusy = false, false
end

FruitGachaService = {Next = 0, Remote = nil}
function FruitGachaService:Invoke(payload)
    self.Remote = self.Remote and self.Remote.Parent and self.Remote or findRemoteFunction("GachaNetworkRF")
    if not self.Remote then return false, "GachaNetworkRF is not available yet" end
    return pcall(self.Remote.InvokeServer, self.Remote, payload)
end
local function requirementMet(record)
    if record == nil then return true end
    if type(record) ~= "table" then return record ~= false end
    return record.RequirementMet ~= false
end
function FruitGachaService:TryRoll(manual)
    if Runtime.Workers.FruitGacha or os.clock() < self.Next then return false end
    self.Next = os.clock() + (manual and 2 or 20)
    worker("FruitGacha", function()
        local ok, check = self:Invoke({Context = "Check", BoxName = "ZiolesGacha", SpokeNPC = "Blox Fruit Gacha"})
        if not ok or type(check) ~= "table" then Runtime.GachaStatus = "Gacha check failed: " .. tostring(check); return end
        local levelOk, cooldownOk, priceOk = requirementMet(check.Level), requirementMet(check.Cooldown), requirementMet(check.Price)
        local restricted = check.PaidRandomItemsRestricted and check.PaidRandomItemsRestricted.Value == true
        local silverReady = check.Keys and check.Keys.Silver and check.Keys.Silver.RequirementMet == true
        local price = tonumber(check.Price and (check.Price.Value or check.Price.Price)) or 0
        if not levelOk then Runtime.GachaStatus = "Blox Fruit Gacha level requirement is not met"; return end
        if restricted then Runtime.GachaStatus = "Random paid items are restricted on this account"; return end
        if silverReady then Runtime.GachaStatus = "Silver Key is available; auto-roll paused so it will not consume the key"; return end
        if not cooldownOk then Runtime.GachaStatus = "Zioles roll is on cooldown"; return end
        if not priceOk or beli() < price + math.max(0, Config.FruitMoneyReserve) then
            Runtime.GachaStatus = string.format("Waiting for Beli · price $%s · reserve $%s", tostring(price), tostring(Config.FruitMoneyReserve)); return
        end
        local invoked, purchased, purchaseError = self:Invoke({Context = "Purchase", BoxName = "ZiolesGacha"})
        if invoked and purchased == true then
            Runtime.Counters.FruitRolls += 1; Runtime.GachaStatus = "Rolled a physical fruit through Zioles"; notify("Zioles fruit roll completed")
        else
            local detail = purchaseError and (type(purchaseError) == "table" and purchaseError.ErrorMessage or tostring(purchaseError)) or tostring(purchased)
            Runtime.GachaStatus = "Fruit roll failed: " .. tostring(detail)
        end
    end)
    return true
end
function FruitGachaService:Step() if Config.AutoRandomFruit then self:TryRoll(false) end end

FruitShopService = {Next = 0, Buying = false, Stock = {}, Display = {}, DisplayToInternal = {}}
function FruitShopService:Refresh(force)
    if (not force and os.clock() < self.Next) or RemoteService.Busy then return false end
    self.Next = os.clock() + (force and 2 or 15)
    local advanced = Config.FruitDealer == "Advanced"
    Runtime.FruitShopStatus = "Refreshing " .. string.lower(Config.FruitDealer) .. " dealer stock…"
    return RemoteService:Call("FruitStock", force and 1 or 10, {"GetFruits", advanced}, function(ok, result)
        if not ok or type(result) ~= "table" then Runtime.FruitShopStatus = "GetFruits failed"; return end
        self.Stock, self.Display, self.DisplayToInternal = result, {}, {}
        for _, item in ipairs(result) do
            if type(item) == "table" and type(item.Name) == "string" then
                local display = prettyFruitName(item.Name)
                if self.DisplayToInternal[display] then display = display .. " [" .. item.Name .. "]" end
                self.DisplayToInternal[display] = item.Name; table.insert(self.Display, display)
            end
        end
        table.sort(self.Display)
        Runtime.FruitShopStatus = string.format("%s dealer · %d fruits loaded", Config.FruitDealer, #self.Display)
    end)
end
function FruitShopService:SelectedEntry()
    local wanted = self.DisplayToInternal[Config.StockFruit]
    if not wanted then return nil end
    for _, item in ipairs(self.Stock) do if type(item) == "table" and item.Name == wanted then return item end end
end
function FruitShopService:BuySelected(manual)
    if self.Buying or RemoteService.Busy then return false end
    if Config.StockFruit == "Select fruit" then Runtime.FruitShopStatus = "Select a fruit first"; return false end
    local entry = self:SelectedEntry()
    if not entry then self:Refresh(true); Runtime.FruitShopStatus = "Refreshing stock before purchase…"; return false end
    if entry.Offsale == true or entry.OnSale == false then Runtime.FruitShopStatus = Config.StockFruit .. " is not currently in stock"; return false end
    local price = tonumber(entry.Price) or 0
    if beli() < price + math.max(0, Config.FruitMoneyReserve) then Runtime.FruitShopStatus = string.format("Need $%s plus $%s reserve", tostring(price), tostring(Config.FruitMoneyReserve)); return false end
    local args = {"PurchaseRawFruit", entry.Name, Config.FruitDealer == "Advanced"}
    if entry.Name == "Dragon-Dragon" then table.insert(args, Config.DragonType) end
    self.Buying = true; Runtime.FruitShopStatus = "Buying " .. Config.StockFruit .. "…"
    return RemoteService:Call("FruitBuy", 3, args, function(ok, result)
        self.Buying = false
        if ok and result then
            Runtime.Counters.Purchases += 1; Runtime.FruitShopStatus = "Purchased " .. Config.StockFruit .. " with Beli"; notify("Purchased fruit: " .. Config.StockFruit)
            if Config.AutoBuyStockFruit then Config.AutoBuyStockFruit = false; if Runtime.Controls and Runtime.Controls.AutoBuyStockFruit then Runtime.Controls.AutoBuyStockFruit:Set(false) end end
        else Runtime.FruitShopStatus = "Purchase failed or fruit left stock"; self.Next = 0 end
    end)
end
function FruitShopService:Step() self:Refresh(false); if Config.AutoBuyStockFruit then self:BuySelected(false) end end

local SHOP_WEAPONS = {"Slingshot", "Musket", "Flintlock", "Refined Slingshot", "Dual Flintlock", "Cannon", "Katana", "Cutlass", "Dual Katana", "Iron Mace", "Triple Katana", "Pipe", "Dual-Headed Blade", "Bisento"}

-- These flows mirror the current 2026 dialogue scripts from the supplied client dump.
-- Most teachers first issue a non-spending `..., true` probe and only then call the
-- spending/equip command. v1.2.0 skipped that probe; on the current game that can
-- leave the UI sitting on "Trying style" with no useful state information.
local STYLE_TEACHERS = {
    ["Dark Step"] = "Dark Step Teacher",
    ["Electric"] = "Mad Scientist",
    ["Water Kung-fu"] = "Water Kung-fu Teacher",
    ["Dragon Breath"] = "Sabi",
    ["Superhuman"] = "Martial Arts Master",
    ["Death Step"] = "Phoeyu, the Reformed",
    ["Sharkman Karate"] = "Sharkman Teacher",
    ["Electric Claw"] = "Previous Hero",
    ["Dragon Talon"] = "Uzoth",
    ["Godhuman"] = "Ancient Monk",
    ["Sanguine Art"] = "Shafi",
}

local STYLE_PROFILES = {
    ["Dark Step"] = {Probe = {"BuyBlackLeg", true}, Buy = {"BuyBlackLeg"}, Money = 150000, Zero = "Not enough Beli for Dark Step"},
    ["Electric"] = {State = {"ElectroQuestState"}, Probe = {"BuyElectro", true}, Buy = {"BuyElectro"}, Money = 500000, Electric = true},
    ["Water Kung-fu"] = {Gate = {"CheckFishmanKarate"}, Probe = {"BuyFishmanKarate", true}, Buy = {"BuyFishmanKarate"}, Money = 750000, Zero = "Not enough Beli for Water Kung-fu"},
    ["Dragon Breath"] = {Probe = {"BlackbeardReward", "DragonClaw", "1"}, Buy = {"BlackbeardReward", "DragonClaw", "2"}, Fragments = 1500, Zero = "Need 1,500 fragments for Dragon Breath"},
    ["Superhuman"] = {Probe = {"BuySuperhuman", true}, Buy = {"BuySuperhuman"}, Money = 3000000, Zero = "Not enough Beli for Superhuman", Three = "Superhuman mastery prerequisites are not met yet"},
    ["Death Step"] = {Probe = {"BuyDeathStep", true}, Buy = {"BuyDeathStep"}, Money = 2500000, Fragments = 5000, Zero = "Need more Beli/fragments for Death Step", Three = "Death Step prerequisites are not met yet"},
    ["Sharkman Karate"] = {Probe = {"BuySharkmanKarate", true}, Buy = {"BuySharkmanKarate"}, Money = 2500000, Fragments = 5000, Zero = "Need more Beli/fragments for Sharkman Karate", Three = "Sharkman Karate prerequisites/Water Key are not ready"},
    ["Electric Claw"] = {Probe = {"BuyElectricClaw", true}, Buy = {"BuyElectricClaw"}, Money = 3000000, Fragments = 5000, Zero = "Need more Beli/fragments for Electric Claw", Three = "Electric Claw mastery prerequisite is not met yet", Four = "Electric Claw Mansion challenge is still required"},
    ["Dragon Talon"] = {Probe = {"BuyDragonTalon", true}, Buy = {"BuyDragonTalon"}, Money = 3000000, Fragments = 5000, Zero = "Need more Beli/fragments for Dragon Talon", Three = "Dragon Talon prerequisites/Fire Essence are not ready"},
    ["Godhuman"] = {Probe = {"BuyGodhuman", true}, Buy = {"BuyGodhuman"}, Money = 5000000, Fragments = 5000, Zero = "Need more Beli/fragments for Godhuman", Three = "Godhuman mastery/material prerequisites are not met yet"},
    ["Sanguine Art"] = {Probe = {"BuySanguineArt", true}, Buy = {"BuySanguineArt"}, Money = 5000000, Fragments = 5000, Zero = "Need more Beli/fragments for Sanguine Art", Three = "Sanguine Art prerequisites are not met yet"},
}
local STYLE_NAMES = {"Dark Step", "Electric", "Water Kung-fu", "Dragon Breath", "Superhuman", "Death Step", "Sharkman Karate", "Electric Claw", "Dragon Talon", "Godhuman", "Sanguine Art"}

-- Current Ability Teacher / Instinct Teacher flows from the supplied 2026 dump.
-- Ability Teacher uses CommF_("BuyHaki", code): 1 learned, 0 insufficient
-- money, 2 already known. Instinct uses KenTalk Start/Buy and has its own
-- eligibility gate. All of these are legitimate in-game money purchases.
local HAKI_PROFILES = {
    ["Aura"] = {Teacher = "Ability Teacher", Money = 25000, Code = "Buso", Label = "Aura"},
    ["Air Jump"] = {Teacher = "Ability Teacher", Money = 10000, Code = "Geppo", Label = "Air Jump"},
    ["Flash Step"] = {Teacher = "Ability Teacher", Money = 100000, Code = "Soru", Label = "Flash Step"},
    ["Instinct"] = {Teacher = "Instinct Teacher", Money = 750000, Instinct = true, Label = "Instinct"},
}
local HAKI_NAMES = {"Aura", "Air Jump", "Flash Step", "Instinct"}

local function fragments()
    local data = Player and Player:FindFirstChild("Data")
    local amount = value(data, "Fragments", nil)
    if type(amount) ~= "number" then amount = value(data, "Fragment", 0) end
    return tonumber(amount) or 0
end

PurchaseService = {
    NextWeapon = 0, NextStyle = 0, NextHaki = 0, StylePhase = "Idle", HakiPhase = "Idle",
    TravelStyle = nil, TravelAbility = nil, TravelGoal = nil, TravelStage = nil, TravelManual = false,
    TeacherScanAt = 0, TeacherCache = {},
}

function PurchaseService:HasTravelWork()
    return self.TravelGoal ~= nil and (self.TravelStyle ~= nil or self.TravelAbility ~= nil)
end

function PurchaseService:TeacherPosition(style, origin, force)
    local teacherName = STYLE_TEACHERS[style]
    if not teacherName then return nil end
    local now = os.clock()
    local cached = self.TeacherCache[style]
    if not force and cached and cached.Position and now < (cached.Until or 0) then return cached.Position end

    local best, bestDistance
    origin = origin or (select(3, char()) and select(3, char()).Position) or Vector3.zero
    local roots = {workspace:FindFirstChild("NPCs"), RS:FindFirstChild("NPCs")}
    for _, root in ipairs(roots) do
        if root then
            for _, npc in ipairs(root:GetDescendants()) do
                if (npc:IsA("Model") or npc:IsA("BasePart")) and npc.Name == teacherName then
                    local p = pos(npc)
                    if p then
                        local d = (p - origin).Magnitude
                        if not bestDistance or d < bestDistance then best, bestDistance = p, d end
                    end
                end
            end
        end
    end
    if best then self.TeacherCache[style] = {Position = best, Until = now + 5} end
    return best
end

function PurchaseService:AbilityTeacherPosition(ability, origin, force)
    local profile = HAKI_PROFILES[ability]
    local teacherName = profile and profile.Teacher
    if not teacherName then return nil end
    local cacheKey = "Ability:" .. ability
    local now = os.clock()
    local cached = self.TeacherCache[cacheKey]
    if not force and cached and cached.Position and now < (cached.Until or 0) then return cached.Position end

    local best, bestDistance
    origin = origin or (select(3, char()) and select(3, char()).Position) or Vector3.zero
    for _, root in ipairs({workspace:FindFirstChild("NPCs"), RS:FindFirstChild("NPCs")}) do
        if root then
            for _, npc in ipairs(root:GetDescendants()) do
                if (npc:IsA("Model") or npc:IsA("BasePart")) and npc.Name == teacherName then
                    local p = pos(npc)
                    if p then
                        local d = (p - origin).Magnitude
                        if not bestDistance or d < bestDistance then best, bestDistance = p, d end
                    end
                end
            end
        end
    end
    if best then self.TeacherCache[cacheKey] = {Position = best, Until = now + 5} end
    return best
end

function PurchaseService:FallbackAbilityArea(ability)
    if Runtime.Sea ~= "Sea1" then return nil end
    local profile = HAKI_PROFILES[ability]
    if not profile then return nil end
    if profile.Teacher == "Ability Teacher" then
        -- Frozen Village; once this area streams, the exact Ability Teacher is
        -- resolved dynamically before any purchase command is sent.
        local points = GameData.sea1NPCPositions and GameData.sea1NPCPositions.SnowQuest
        if points and points[1] then return vec(points[1]) end
        return Vector3.new(1400.6, 77.4, -1311.3)
    elseif profile.Teacher == "Instinct Teacher" then
        -- Upper Sky. This rough destination is only used to stream the island;
        -- the exact Instinct Teacher model is then resolved live.
        local points = GameData.sea1NPCPositions and GameData.sea1NPCPositions.SkyExp2Quest
        if points and points[1] then return vec(points[1]) end
        return Vector3.new(-7033.1, 5590.6, 1353.1)
    end
    return nil
end

function PurchaseService:BeginAbilityTravel(ability, manual)
    if self:HasTravelWork() then return true end
    local profile = HAKI_PROFILES[ability]
    local _, _, root = char()
    if not profile or not root then return false end
    if Runtime.Sea ~= "Sea1" then
        Runtime.PurchaseStatus = ability .. " teacher is in First Sea · return to First Sea to purchase"
        self.HakiPhase = "Waiting"
        self.NextHaki = os.clock() + 8
        return false
    end
    local teacher = self:AbilityTeacherPosition(ability, root.Position, true)
    local goal, stage = teacher, "Teacher"
    if not goal then goal, stage = self:FallbackAbilityArea(ability), "Area" end
    if not goal then
        Runtime.PurchaseStatus = "Could not resolve the " .. tostring(profile.Teacher) .. " location"
        self.NextHaki = os.clock() + 5
        return false
    end
    if (goal - root.Position).Magnitude <= (stage == "Teacher" and 12 or 30) then
        if stage == "Teacher" then return false end
        teacher = self:AbilityTeacherPosition(ability, root.Position, true)
        if teacher then goal, stage = teacher, "Teacher" else
            Runtime.PurchaseStatus = tostring(profile.Teacher) .. " is not streamed yet; rescanning nearby…"
            self.NextHaki = os.clock() + 1
            return false
        end
    end
    self.TravelAbility, self.TravelGoal, self.TravelStage, self.TravelManual = ability, goal, stage, manual == true
    self.HakiPhase = "Travel"
    self.NextHaki = 0
    Runtime.PurchaseStatus = stage == "Teacher"
        and ("Travelling to " .. tostring(profile.Teacher) .. " before buying " .. ability .. "…")
        or ("Travelling to the " .. ability .. " teacher area…")
    return true
end

function PurchaseService:FallbackTeacherArea(style)
    -- First Sea Dark Step is at Pirate Village. The exact teacher model can be
    -- streamed out while the player is in Desert/Jungle, so travel to the live
    -- Pirate quest area first and re-resolve the NPC there.
    if style == "Dark Step" and Runtime.Sea == "Sea1" then
        local points = GameData.sea1NPCPositions and GameData.sea1NPCPositions.BuggyQuest1
        if points and points[1] then return vec(points[1]) end
        return Vector3.new(-1151.6, 18, 3863.1)
    end
    return nil
end

function PurchaseService:BeginTeacherTravel(style, manual)
    if self:HasTravelWork() then return true end
    local _, _, root = char()
    if not root then return false end
    local teacher = self:TeacherPosition(style, root.Position, true)
    local goal, stage = teacher, "Teacher"
    if not goal then goal, stage = self:FallbackTeacherArea(style), "Area" end
    if not goal then return false end
    if (goal - root.Position).Magnitude <= (stage == "Teacher" and 12 or 30) then
        if stage == "Teacher" then return false end
        -- Already at the rough island area: force a fresh NPC lookup before
        -- deciding the seller is unavailable.
        teacher = self:TeacherPosition(style, root.Position, true)
        if teacher then goal, stage = teacher, "Teacher" else return false end
    end
    self.TravelStyle, self.TravelGoal, self.TravelStage, self.TravelManual = style, goal, stage, manual == true
    Runtime.PurchaseStatus = stage == "Teacher"
        and ("Travelling to " .. tostring(STYLE_TEACHERS[style]) .. " before purchase…")
        or ("Travelling to the " .. style .. " teacher area…")
    self.StylePhase = "Travel"
    self.NextStyle = 0
    return true
end

function PurchaseService:TravelStep(root)
    if not root or not self.TravelGoal then return false end
    local style, ability = self.TravelStyle, self.TravelAbility
    local isAbility = ability ~= nil
    local key = isAbility and ability or style
    if not key then return false end
    local profile = isAbility and HAKI_PROFILES[ability] or nil
    local teacherName = isAbility and (profile and profile.Teacher or ability) or (STYLE_TEACHERS[style] or style)
    local teacher = isAbility and self:AbilityTeacherPosition(ability, root.Position, false) or self:TeacherPosition(style, root.Position, false)
    if teacher then
        self.TravelGoal, self.TravelStage = teacher, "Teacher"
    end
    local goal = self.TravelGoal
    local tolerance = self.TravelStage == "Teacher" and 9 or 28
    local distance = (goal - root.Position).Magnitude
    if distance > tolerance then
        Combat:Stop(); Runtime.Target = nil
        state("SHOP_TRAVEL", "Going to " .. tostring(teacherName) .. " · " .. math.floor(distance) .. " studs")
        Runtime.PurchaseStatus = "Travelling to " .. tostring(teacherName) .. " · " .. math.floor(distance) .. " studs"
        local prefix = isAbility and "AbilityTeacher:" or "StyleTeacher:"
        Movement:GoTo("Shop", CFrame.new(goal + Vector3.new(0, 2, 3)), tolerance, true, prefix .. tostring(key) .. ":" .. tostring(self.TravelStage))
        return true
    end

    Movement:Cancel("Reached shop teacher area")
    if self.TravelStage == "Area" then
        local exact = isAbility and self:AbilityTeacherPosition(ability, root.Position, true) or self:TeacherPosition(style, root.Position, true)
        if exact then
            self.TravelGoal, self.TravelStage = exact, "Teacher"
            return true
        end
        Runtime.PurchaseStatus = tostring(teacherName) .. " is not loaded yet; rescanning nearby…"
        self.TeacherCache[isAbility and ("Ability:" .. ability) or style] = nil
        return true
    end

    local wasManual = self.TravelManual
    self.TravelStyle, self.TravelAbility, self.TravelGoal, self.TravelStage, self.TravelManual = nil, nil, nil, nil, false
    Runtime.PurchaseStatus = "Reached " .. tostring(teacherName) .. " · purchasing " .. tostring(key) .. "…"
    if isAbility then
        self.HakiPhase = "Idle"; self.NextHaki = 0
        if wasManual and not Config.AutoBuyHaki then
            task.defer(function() if Runtime.Running then task.wait(0.15); self:BuyHaki(true, true) end end)
        end
    else
        self.StylePhase = "Idle"; self.NextStyle = 0
        if wasManual and not Config.AutoBuyStyle then
            task.defer(function() if Runtime.Running then task.wait(0.15); self:BuyStyle(true, true) end end)
        end
    end
    return true
end

function PurchaseService:StopToggle(key)
    Config[key] = false
    if Runtime.Controls and Runtime.Controls[key] then Runtime.Controls[key]:Set(false) end
end
function PurchaseService:BuyWeapon(manual)
    if RemoteService.Busy or os.clock() < self.NextWeapon then return false end
    self.NextWeapon = os.clock() + (manual and 2 or 20)
    Runtime.PurchaseStatus = "Trying weapon: " .. Config.ShopWeapon
    local started = RemoteService:Call("BuyWeapon", manual and 1 or 10, {"BuyItem", Config.ShopWeapon}, function(ok, result, requiredLevel)
        if not ok then
            Runtime.PurchaseStatus = tostring(result):find("timed out", 1, true) and "Weapon shop did not answer; retrying" or "Weapon purchase request failed: " .. tostring(result)
            self.NextWeapon = os.clock() + 4
            return
        end
        if result == 1 then Runtime.Counters.Purchases += 1; Runtime.PurchaseStatus = "Purchased " .. Config.ShopWeapon; notify("Purchased weapon: " .. Config.ShopWeapon); self:StopToggle("AutoBuyWeapon")
        elseif result == 2 then Runtime.PurchaseStatus = Config.ShopWeapon .. " is already owned"; self:StopToggle("AutoBuyWeapon")
        elseif result == 3 then Runtime.PurchaseStatus = "Requires level " .. tostring(requiredLevel or "higher")
        elseif result == 0 then Runtime.PurchaseStatus = "Not enough Beli for " .. Config.ShopWeapon
        else Runtime.PurchaseStatus = "Weapon response: " .. tostring(result) end
    end, {GenerationBound = false, Timeout = 10})
    if not started then
        Runtime.PurchaseStatus = "Weapon shop is busy; retrying shortly"
        self.NextWeapon = os.clock() + 1
    end
    return started
end

function PurchaseService:StyleResult(style, profile, ok, result)
    if not ok then
        self.StylePhase = "Retry"
        Runtime.PurchaseStatus = tostring(result):find("timed out", 1, true)
            and ("Style server did not answer for " .. style .. "; retrying")
            or ("Fighting style request failed: " .. tostring(result))
        self.NextStyle = os.clock() + 4
        return
    end
    self.StylePhase = "Idle"
    if result == 1 then
        Runtime.Counters.Purchases += 1
        Runtime.PurchaseStatus = style .. " purchased/equipped"
        notify("Fighting style ready: " .. style)
        self:StopToggle("AutoBuyStyle")
    elseif result == 2 then
        Runtime.PurchaseStatus = style .. " is already known/equipped"
        self:StopToggle("AutoBuyStyle")
    elseif type(result) == "string" then
        Runtime.PurchaseStatus = result
    elseif result == 4 and profile.Four then
        Runtime.PurchaseStatus = profile.Four
    elseif result == 3 and profile.Three then
        Runtime.PurchaseStatus = profile.Three
    elseif result == 0 then
        local haveMoney = not profile.Money or beli() >= profile.Money
        local haveFragments = not profile.Fragments or fragments() >= profile.Fragments
        if haveMoney and haveFragments then
            Runtime.PurchaseStatus = "Server declined " .. style .. " despite sufficient displayed currency; staying by the teacher and retrying"
            self.NextStyle = os.clock() + 3
        else
            Runtime.PurchaseStatus = profile.Zero or ("Missing money/fragments or a prerequisite for " .. style)
        end
    else
        Runtime.PurchaseStatus = style .. " response: " .. tostring(result)
    end
end

function PurchaseService:PerformStyleBuy(style, profile, manual)
    self.StylePhase = "Buy"
    local moneyText = profile.Money and (" · $" .. tostring(beli()) .. "/$" .. tostring(profile.Money)) or ""
    Runtime.PurchaseStatus = "Buying/equipping " .. style .. moneyText .. "…"
    local started = RemoteService:Call("BuyStyle", manual and 0.5 or 2, profile.Buy, function(ok, result)
        self:StyleResult(style, profile, ok, result)
    end, {GenerationBound = false, Timeout = 10})
    if not started then
        self.StylePhase = "Retry"
        Runtime.PurchaseStatus = "Style remote slot is busy; retrying shortly"
        self.NextStyle = os.clock() + 1
    end
    return started
end

function PurchaseService:AfterStyleProbe(style, profile, manual, ok, probe)
    if not ok then
        self.StylePhase = "Retry"
        Runtime.PurchaseStatus = tostring(probe):find("timed out", 1, true)
            and ("Style eligibility check timed out for " .. style .. "; retrying")
            or ("Style eligibility check failed: " .. tostring(probe))
        self.NextStyle = os.clock() + 4
        return
    end
    if type(probe) == "string" then
        self.StylePhase = "Waiting"
        Runtime.PurchaseStatus = probe
        return
    end
    if probe == 4 and profile.Four then
        self.StylePhase = "Waiting"
        Runtime.PurchaseStatus = profile.Four
        return
    end
    if probe == 3 and profile.Three then
        self.StylePhase = "Waiting"
        Runtime.PurchaseStatus = profile.Three
        return
    end
    if style == "Dragon Breath" and not probe then
        self.StylePhase = "Waiting"
        Runtime.PurchaseStatus = "Dragon Breath is not available from Sabi yet"
        return
    end
    self:PerformStyleBuy(style, profile, manual)
end

function PurchaseService:HandleElectricState(style, profile, manual, ok, questState)
    if not ok then
        self.StylePhase = "Retry"
        Runtime.PurchaseStatus = "Could not read the Electric prerequisite state"
        self.NextStyle = os.clock() + 4
        return
    end
    -- Current client flow: 0 = prerequisite not started, 1 = waiting for a
    -- Lightning Bolt, 4 = style already known + bolt can be delivered, 5 =
    -- style already known but the research prerequisite is still unfinished.
    if questState == 0 or questState == 5 then
        self.StylePhase = "ElectricQuest"
        Runtime.PurchaseStatus = "Starting Electric prerequisite quest…"
        local started = RemoteService:Call("StylePrereq", 2, {"AcceptElectroQuest"}, function(startOk, result)
            if startOk and result == 1 then Runtime.PurchaseStatus = "Electric prerequisite started · get a Lightning Bolt from a charged cloud"
            else Runtime.PurchaseStatus = "Electric prerequisite could not start yet: " .. tostring(result) end
            self.StylePhase = "Waiting"
        end, {GenerationBound = false, Timeout = 10})
        if not started then Runtime.PurchaseStatus = "Remote busy; Electric prerequisite will retry"; self.NextStyle = os.clock() + 1 end
        return
    elseif questState == 1 then
        self.StylePhase = "Waiting"
        Runtime.PurchaseStatus = "Electric needs a Lightning Bolt from a charged cloud before purchase"
        return
    elseif questState == 4 then
        self.StylePhase = "ElectricQuest"
        Runtime.PurchaseStatus = "Electric is already known; delivering the Lightning Bolt prerequisite…"
        local started = RemoteService:Call("StylePrereq", 2, {"DeliverLightningBolt"}, function(deliverOk, result)
            if deliverOk and result == 1 then
                Runtime.PurchaseStatus = "Electric already known; prerequisite delivery completed"
                self:StopToggle("AutoBuyStyle")
            else Runtime.PurchaseStatus = "Lightning Bolt delivery not ready: " .. tostring(result) end
            self.StylePhase = "Waiting"
        end, {GenerationBound = false, Timeout = 10})
        if not started then Runtime.PurchaseStatus = "Remote busy; Lightning Bolt delivery will retry"; self.NextStyle = os.clock() + 1 end
        return
    end
    self.StylePhase = "Probe"
    Runtime.PurchaseStatus = "Checking Electric purchase state…"
    local started = RemoteService:Call("StyleProbe", 1, profile.Probe, function(probeOk, probe)
        self:AfterStyleProbe(style, profile, manual, probeOk, probe)
    end, {GenerationBound = false, Timeout = 10})
    if not started then Runtime.PurchaseStatus = "Remote busy; Electric check will retry"; self.NextStyle = os.clock() + 1 end
end

function PurchaseService:BuyStyle(manual, skipTeacherTravel)
    if RemoteService.Busy or os.clock() < self.NextStyle then return false end
    local style = Config.FightingStyle
    local profile = STYLE_PROFILES[style]
    if not profile then Runtime.PurchaseStatus = "Unsupported fighting style selection"; return false end

    local currentBeli = beli()
    if profile.Money and currentBeli < profile.Money then
        self.StylePhase = "Waiting"
        Runtime.PurchaseStatus = string.format("%s needs $%s Beli · you have $%s", style, tostring(profile.Money), tostring(currentBeli))
        self.NextStyle = os.clock() + (manual and 2 or 8)
        return false
    end
    local currentFragments = fragments()
    if profile.Fragments and currentFragments < profile.Fragments then
        self.StylePhase = "Waiting"
        Runtime.PurchaseStatus = string.format("%s needs %s fragments · you have %s", style, tostring(profile.Fragments), tostring(currentFragments))
        self.NextStyle = os.clock() + (manual and 2 or 8)
        return false
    end

    -- Current live servers can reject a teacher purchase made from an unrelated
    -- island even when the replicated Beli count is sufficient. Resolve and
    -- approach the actual teacher before sending the spending command.
    if not skipTeacherTravel and self:BeginTeacherTravel(style, manual) then
        return false
    end

    self.NextStyle = os.clock() + (manual and 2 or 18)

    if profile.Gate then
        self.StylePhase = "Gate"
        Runtime.PurchaseStatus = "Checking " .. style .. " teacher access…"
        local started = RemoteService:Call("StyleGate", 1, profile.Gate, function(ok, available)
            if not ok then Runtime.PurchaseStatus = "Could not verify " .. style .. " teacher access"; self.NextStyle = os.clock() + 4; return end
            if not available then Runtime.PurchaseStatus = style .. " teacher is not available in your current state"; self.StylePhase = "Waiting"; return end
            self.StylePhase = "Probe"
            Runtime.PurchaseStatus = "Checking " .. style .. " purchase state…"
            local probeStarted = RemoteService:Call("StyleProbe", 1, profile.Probe, function(probeOk, probe)
                self:AfterStyleProbe(style, profile, manual, probeOk, probe)
            end, {GenerationBound = false, Timeout = 10})
            if not probeStarted then Runtime.PurchaseStatus = "Remote busy; style check will retry"; self.NextStyle = os.clock() + 1 end
        end, {GenerationBound = false, Timeout = 10})
        if not started then Runtime.PurchaseStatus = "Remote busy; teacher access check will retry"; self.NextStyle = os.clock() + 1 end
        return started
    end

    if profile.State and profile.Electric then
        self.StylePhase = "State"
        Runtime.PurchaseStatus = "Checking Electric prerequisite…"
        local started = RemoteService:Call("StyleState", 1, profile.State, function(ok, questState)
            self:HandleElectricState(style, profile, manual, ok, questState)
        end, {GenerationBound = false, Timeout = 10})
        if not started then Runtime.PurchaseStatus = "Remote busy; Electric state check will retry"; self.NextStyle = os.clock() + 1 end
        return started
    end

    self.StylePhase = "Probe"
    Runtime.PurchaseStatus = "Checking " .. style .. " purchase state…"
    local started = RemoteService:Call("StyleProbe", 1, profile.Probe, function(ok, probe)
        self:AfterStyleProbe(style, profile, manual, ok, probe)
    end, {GenerationBound = false, Timeout = 10})
    if not started then
        self.StylePhase = "Retry"
        Runtime.PurchaseStatus = "Remote busy; style check will retry shortly"
        self.NextStyle = os.clock() + 1
    end
    return started
end
function PurchaseService:FinishHaki(ability, resultText)
    Runtime.Counters.Purchases += 1
    Runtime.PurchaseStatus = resultText or (ability .. " ready")
    notify(ability .. " ready")
    self.HakiPhase = "Ready"
    self:StopToggle("AutoBuyHaki")
    if ability == "Aura" then
        Config.AutoAura = true
        if Runtime.Controls and Runtime.Controls.AutoAura then Runtime.Controls.AutoAura:Set(true) end
    end
end

function PurchaseService:BuyHaki(manual, skipTeacherTravel)
    if RemoteService.Busy or os.clock() < self.NextHaki then return false end
    local ability = Config.HakiAbility
    local profile = HAKI_PROFILES[ability]
    if not profile then Runtime.PurchaseStatus = "Unsupported Haki/ability selection"; return false end

    local money = beli()
    if profile.Money and money < profile.Money then
        self.HakiPhase = "Waiting"
        Runtime.PurchaseStatus = string.format("%s needs $%s Beli · you have $%s", ability, tostring(profile.Money), tostring(money))
        self.NextHaki = os.clock() + (manual and 2 or 8)
        return false
    end

    if not skipTeacherTravel and self:BeginAbilityTravel(ability, manual) then return false end
    self.NextHaki = os.clock() + (manual and 2 or 15)

    if profile.Instinct then
        self.HakiPhase = "Check"
        Runtime.PurchaseStatus = "Checking Instinct eligibility…"
        local started = RemoteService:Call("HakiCheck", 1, {"KenTalk", "Start"}, function(ok, stateValue)
            if not ok then
                Runtime.PurchaseStatus = "Instinct Teacher did not answer: " .. tostring(stateValue)
                self.NextHaki = os.clock() + 4; self.HakiPhase = "Retry"; return
            end
            if stateValue == 0 then
                Runtime.PurchaseStatus = "Instinct is already learned"
                self.HakiPhase = "Ready"; self:StopToggle("AutoBuyHaki"); return
            elseif stateValue ~= 1 then
                Runtime.PurchaseStatus = "Instinct prerequisites are not met yet · teacher state " .. tostring(stateValue)
                self.HakiPhase = "Waiting"; self.NextHaki = os.clock() + 10; return
            end
            self.HakiPhase = "Buy"
            Runtime.PurchaseStatus = "Buying Instinct for $750,000…"
            local bought = RemoteService:Call("HakiBuy", 1, {"KenTalk", "Buy"}, function(buyOk, buyResult)
                if not buyOk then Runtime.PurchaseStatus = "Instinct purchase failed: " .. tostring(buyResult); self.NextHaki = os.clock() + 4; return end
                -- Current dialogue treats 0 as a successful Instinct purchase.
                if buyResult == 0 then self:FinishHaki("Instinct", "Instinct purchased")
                else Runtime.PurchaseStatus = "Instinct purchase was declined · response " .. tostring(buyResult); self.NextHaki = os.clock() + 6 end
            end, {GenerationBound = false, Timeout = 10})
            if not bought then Runtime.PurchaseStatus = "Remote busy; Instinct purchase will retry"; self.NextHaki = os.clock() + 1 end
        end, {GenerationBound = false, Timeout = 10})
        if not started then Runtime.PurchaseStatus = "Remote busy; Instinct check will retry"; self.NextHaki = os.clock() + 1 end
        return started
    end

    self.HakiPhase = "Buy"
    Runtime.PurchaseStatus = "Buying " .. ability .. " for $" .. tostring(profile.Money) .. "…"
    local started = RemoteService:Call("HakiBuy", 1, {"BuyHaki", profile.Code}, function(ok, result)
        if not ok then Runtime.PurchaseStatus = ability .. " purchase request failed: " .. tostring(result); self.NextHaki = os.clock() + 4; return end
        if result == 1 then
            self:FinishHaki(ability, ability .. " purchased")
        elseif result == 2 then
            Runtime.PurchaseStatus = ability .. " is already learned"
            self.HakiPhase = "Ready"; self:StopToggle("AutoBuyHaki")
            if ability == "Aura" then Config.AutoAura = true; if Runtime.Controls and Runtime.Controls.AutoAura then Runtime.Controls.AutoAura:Set(true) end end
        elseif result == 0 then
            -- Money was checked locally immediately before the request. If the
            -- replicated balance says enough, report a server decline rather than
            -- falsely claiming the player is broke.
            if beli() >= (profile.Money or 0) then Runtime.PurchaseStatus = ability .. " purchase declined by server despite sufficient Beli; staying by teacher and retrying"
            else Runtime.PurchaseStatus = "Not enough Beli for " .. ability end
            self.NextHaki = os.clock() + 6
        else
            Runtime.PurchaseStatus = ability .. " response: " .. tostring(result); self.NextHaki = os.clock() + 6
        end
    end, {GenerationBound = false, Timeout = 10})
    if not started then Runtime.PurchaseStatus = "Remote busy; " .. ability .. " purchase will retry"; self.NextHaki = os.clock() + 1 end
    return started
end

function PurchaseService:Step()
    if Config.AutoBuyWeapon then self:BuyWeapon(false) end
    if Config.AutoBuyStyle and not self:HasTravelWork() then self:BuyStyle(false) end
    if Config.AutoBuyHaki and not self:HasTravelWork() then self:BuyHaki(false) end
end

-- Item-NPC, accessories, trinkets, enchants and Auto Best Gear were removed in v1.6.7.

local Controller = {TargetName = nil, LastHealth = nil, DamageAt = 0, NoTargetAt = 0, RecoveryCount = 0, WaitAnchor = nil,
    M1Target = nil, M1Confirmed = false, M1StartedAt = 0, M1AttemptAt = 0, M1AttemptHealth = nil}
function Controller:Recover(reason, blacklist)
    Runtime.LastRecovery = reason
    Runtime.Counters.Recoveries = Runtime.Counters.Recoveries + 1
    if blacklist and Runtime.Target then EnemyService.Blocked[Runtime.Target] = os.clock() + 45 end
    self.RecoveryCount = self.RecoveryCount + 1
    release(reason)
    Runtime.PauseUntil = os.clock() + math.min(12, self.RecoveryCount * 2)
    self.LastHealth, self.WaitAnchor = nil, nil
    state("RECOVERY", reason)
    log("Recovery", reason)
end
function Controller:EnsureQuest(q, origin)
    local active, known = QuestService:Active()
    if not known then
        -- Auto Level owns quest selection. If direct guide-state sync is unavailable,
        -- normalize the server to a known no-quest state once instead of stalling.
        state("QUEST_SYNC", "Synchronizing current quest state")
        if os.clock() >= (QuestService.UnknownResetAt or 0) and not RemoteService.Busy then
            QuestService.UnknownResetAt = os.clock() + 6
            RemoteService:Call("Quest", 2, {"AbandonQuest"}, function(ok)
                if ok then
                    Runtime.ActiveQuest = nil
                    Runtime.ActiveQuestKnown = true
                    QuestService.PendingUntil = 0
                    QuestService.PendingQuest = nil
                    log("Quest", "Quest state normalized through AbandonQuest fallback")
                end
            end)
        end
        return false
    end
    if QuestService:Matches(active, q) then
        QuestService.PendingUntil = 0; QuestService.PendingQuest = nil
        return true
    end
    Combat:Stop()
    Runtime.Target = nil
    if os.clock() < QuestService.PendingUntil then
        if Movement.Connection then Movement:Cancel("Waiting for quest confirmation") end
        state("QUEST_CHECK", "Waiting for quest confirmation"); return false
    end
    if QuestService.PendingQuest then
        QuestService:Reject(QuestService.PendingQuest, "Quest state did not confirm within 8 seconds")
        QuestService.PendingQuest = nil
        return false
    end
    if active then
        if (self.AbandonAttempts or 0) >= 3 then
            Movement:Cancel("Quest abandonment unconfirmed")
            state("QUEST_BLOCKED", "Quest did not abandon after 3 requests. Check it in-game, then toggle the farm off/on.")
            return false
        end
        Movement:Cancel("Quest mismatch")
        state("QUEST_MISMATCH", "Abandoning the previous quest")
        if RemoteService:Call("Quest", 3, {"AbandonQuest"}, function(ok)
            if not ok then QuestService:Reject(q, "AbandonQuest failed") end
        end) then QuestService.PendingUntil = os.clock() + 3; self.AbandonAttempts = (self.AbandonAttempts or 0) + 1 end
        return false
    end
    self.AbandonAttempts = 0
    local destination = QuestService:Position(q.Id, origin)
    if not destination then QuestService:Reject(q, "Quest NPC location unavailable"); return false end
    if (destination - origin).Magnitude > 8 then
        state("TRAVEL_TO_QUEST", QuestService:NPCName(q.Id) or q.Id)
        Movement:GoTo(Runtime.Owner, CFrame.new(destination + Vector3.new(0, 1, 3)), 4, true, "Quest:" .. q.Key)
        return false
    end
    Movement:Cancel("At quest NPC")
    state("START_QUEST", q.Id .. " · " .. q.Index)
    if RemoteService:Call("Quest", 3, {"StartQuest", q.Id, q.Index}, function(ok, response)
        if not ok or response ~= 0 then QuestService:Reject(q, "StartQuest returned " .. tostring(response)) end
    end) then
        QuestService.PendingUntil = os.clock() + 8; QuestService.PendingQuest = q
    end
    return false
end
function Controller:BossRecord(level, origin)
    if Config.BossQuest then return QuestService:Choose(level, origin, Config.Boss) end
    if Config.Boss ~= "Auto available" then return {Target = Config.Boss, Boss = true} end
    local selected, score
    for model in pairs(EnemyService.Models) do
        local h, r = EnemyService:Parts(model)
        if h and (model:GetAttribute("IsBoss") == true or tostring(model:GetAttribute("DisplayName") or model.Name):find("[Boss]", 1, true)) and (not EnemyService:IsContested(model) or EnemyService:IsOurs(model)) then
            local d = (origin - r.Position).Magnitude
            if not score or d < score then selected, score = {Target = normalize(model.Name), Boss = true}, d end
        end
    end
    return selected
end
function Controller:Step()
    EnemyService:UpdateDamageOwnership()
    local owner = selectedOwner()
    if owner ~= Runtime.Owner then
        release("Farm mode changed"); Runtime.Owner = owner
        QuestService.PendingUntil, QuestService.PendingQuest = 0, nil
        self.WaitAnchor, self.LastHealth, self.LastHumanoid, self.AbandonAttempts = nil, nil, nil, 0
        self.NoTargetAt = os.clock()
    end
    if not owner then state("IDLE", "Choose a farm to start"); return end
    if os.clock() < Runtime.PauseUntil then return end
    local c, _, r = char()
    if not c then
        release("Waiting for respawn"); state("WAIT_CHARACTER", "Waiting for a living character"); return
    end
    if not Player.Team then release("Team selection"); state("SELECT_TEAM", "Choose Pirates or Marines in the game"); return end
    if not Runtime.Sea then Movement:Cancel("Unknown realm"); Combat:Stop(); state("DETECT_WORLD", "Detecting current sea (PlaceId/Realm fallback)"); return end
    if owner == "Shop" then
        Combat:Stop(); Runtime.Target = nil
        PurchaseService:TravelStep(r)
        return
    end
    -- Spawned fruit collection shares the current farm movement owner so it can
    -- safely detour and then resume.  Once PuckAFK has landed damage on a target,
    -- FruitPickupService refuses to interrupt that enemy or boss until it dies.
    if FruitPickupService and Config.AutoCollectSpawnedFruits and FruitPickupService:Step(owner) then return end
    if owner == "Fruit" then state("IDLE", "Waiting for the next naturally spawned fruit"); return end
    -- Core Auto Level no longer waits for game modules. Quests are bundled and
    -- combat falls back to real input if CombatController/CombatUtil cannot load.
    if not Runtime.ActiveQuestKnown then QuestService:SyncActive(false) end
    if RemoteService.Busy and os.clock() - RemoteService.Busy.Started > 12 then
        Movement:Cancel("Server response delayed"); Combat:Stop()
        state("WAIT_SERVER", RemoteService.Busy.Label .. " is taking over 12 seconds; no duplicate request sent")
        return
    end
    if Movement.Error then
        local reason = Movement.Error; Movement.Error = nil
        if Runtime.Target and EnemyService:IsOurs(Runtime.Target) and EnemyService:Parts(Runtime.Target) then
            Movement:Cancel("Retry engaged target")
            Runtime.PauseUntil = os.clock() + 0.75
            self.DamageAt = os.clock()
            state("RECOVERY", reason .. " · keeping engaged target")
            return
        end
        self:Recover(reason, true); return
    end
    local level = value(Player:FindFirstChild("Data"), "Level", nil)
    if type(level) ~= "number" then state("WAIT_DATA", "Waiting for Data.Level"); return end
    QuestService:Build()
    WeaponService:Refresh()
    local q = Runtime.Quest
    local engaged = Runtime.Target and EnemyService:IsOurs(Runtime.Target) and EnemyService:Parts(Runtime.Target) ~= nil
    if owner == "Level" then
        local failure = q and QuestService.Failures[q.Key]
        local failed = failure and os.clock() < failure.Until
        local changed = self.SelectionLevel ~= level or self.SelectionSea ~= Runtime.Sea
        if not engaged and not QuestService.PendingQuest and (not q or failed or changed) then
            if q or os.clock() >= (self.NextQuestChoice or 0) then
                q = QuestService:Choose(level, r.Position)
                self.SelectionLevel, self.SelectionSea = level, Runtime.Sea
                self.NextQuestChoice = os.clock() + 2
            end
        end
    elseif owner == "Boss" then
        if not q then q = self:BossRecord(level, r.Position) end
    else
        if Config.Enemy == "Select enemy" then state("SELECT_TARGET", "Choose an enemy on the Enemies tab"); return end
        q = {Target = Config.Enemy}
    end
    Runtime.Quest = q
    if not q then
        Movement:Cancel("No available quest"); Combat:Stop()
        state(owner == "Boss" and "WAIT_BOSS" or "NO_QUEST",
            owner == "Boss" and "No eligible boss available; checking spawns" or "No eligible quest with a verified NPC location in this sea")
        return
    end
    if q.Id and not engaged and not self:EnsureQuest(q, r.Position) then return end
    if not engaged and self.TargetName ~= q.Target then
        Combat:Stop(); Runtime.Target = nil; self.LastHealth = nil
        self.WaitAnchor, self.TargetName, self.NoTargetAt = nil, q.Target, os.clock()
    end
    local target = Runtime.Target
    local targetHumanoid, targetRoot, targetHitPart = EnemyService:Parts(target)
    if targetHumanoid and EnemyService:IsContested(target) and not EnemyService:IsOurs(target) then
        Combat:Stop(); Movement:Cancel("Target contested")
        EnemyService.Blocked[target] = os.clock() + Config.ContestedSeconds
        Runtime.Target = nil; self.LastHealth = nil; self.NoTargetAt = os.clock()
        state("SELECT_TARGET", "Another player is damaging " .. q.Target .. " · choosing a different one")
        target, targetHumanoid, targetRoot, targetHitPart = nil, nil, nil, nil
    end
    if target and not targetHumanoid then
        local oldHumanoid = target:FindFirstChildOfClass("Humanoid") or self.LastHumanoid
        local killed = oldHumanoid and oldHumanoid.Health <= 0
        if killed then Runtime.Counters.Targets = Runtime.Counters.Targets + 1 end
        Combat:Stop(); Runtime.Target = nil; self.LastHealth = nil
        self.NoTargetAt = os.clock()
        if owner == "Boss" and killed then
            if not Config.RepeatBoss then
                Config.AutoBoss = false
                if Runtime.Controls.AutoBoss then Runtime.Controls.AutoBoss:Set(false) end
                release("Boss defeated"); notify("Boss defeated; Boss Farm stopped")
                return
            end
            Runtime.Quest = nil
        end
        -- Keep the current farm offset while acquiring another enemy.
        self.WaitAnchor = r.CFrame
    end
    if not Runtime.Target then
        Runtime.Target = EnemyService:Select(q.Target, r.Position)
        self.LastHealth, self.DamageAt = nil, os.clock()
        Runtime.M1Status = Runtime.Target and ("Ready on " .. q.Target) or "Waiting for target"
    end
    targetHumanoid, targetRoot, targetHitPart = EnemyService:Parts(Runtime.Target)
    if DodgeService then DodgeService:Observe(Runtime.Target, targetHumanoid, targetRoot) end
    if not targetHumanoid then
        Combat:Stop()
        local spawn = EnemyService:NearestSpawn(q.Target, r.Position)
        local waited = math.floor(os.clock() - self.NoTargetAt)
        state(owner == "Boss" and "WAIT_BOSS" or "WAIT_SPAWN", q.Target .. " · waiting " .. waited .. "s")
        if spawn and (spawn - r.Position).Magnitude > 35 then
            Movement:GoTo(owner, CFrame.new(spawn + Vector3.new(0, 3, 0)), 10, true, "Spawn:" .. q.Target)
        elseif self.WaitAnchor then
            Movement:GoTo(owner, self.WaitAnchor, 3, true, "Hold")
        else Movement:Cancel("Waiting at spawn") end
        if owner == "Boss" and Config.Boss == "Auto available" and waited > 45 then Runtime.Quest = nil; self.NoTargetAt = os.clock() end
        return
    end

    self.WaitAnchor = nil
    self.LastHumanoid = targetHumanoid
    if self.LastHealth == nil then
        self.DamageAt = os.clock()
    elseif targetHumanoid.Health < self.LastHealth then
        self.DamageAt = os.clock(); Runtime.ProgressAt = self.DamageAt; self.RecoveryCount = 0
        Runtime.M1Status = "Target health decreased (M1 or skill)"
    end
    self.LastHealth = targetHumanoid.Health

    local finishing = Config.Mastery and targetHumanoid.MaxHealth > 0 and targetHumanoid.Health / targetHumanoid.MaxHealth * 100 <= Config.FinishPercent
    local entry = WeaponService:Choose(finishing)
    if not entry then
        Movement:Cancel("No usable weapon"); Combat:Stop()
        state("WAIT_WEAPON", finishing and "Select an available mastery weapon" or "Equip or select a usable weapon")
        return
    end

    if not WeaponService:Equip(entry) then
        state("EQUIP_WEAPON", "Waiting for " .. entry.Tool.Name .. " to equip")
        return
    end
    Runtime.Weapon = entry.Tool.Name
    Combat:Observe(Runtime.Target, targetHumanoid, entry)

    local weaponType = entry.Data and entry.Data.WeaponType or "Unknown"
    local destination = Movement:Position(targetRoot, entry.Data)
    if DodgeService then destination = DodgeService:Apply(destination, targetRoot) end
    Movement:GoTo(owner, destination, weaponType == "Gun" and 3 or 1.25, true, Runtime.Target)

    local distance = (r.Position - targetRoot.Position).Magnitude
    local casting = false

    -- Exact offsets stay authoritative, but range estimation must never block a click
    -- that the game itself would accept.  If movement is locked to this enemy and we
    -- are nearby, always let Combat:Attack send Mouse1 and let Blox Fruits validate it.
    local lockedOn = Runtime.Target ~= nil and Movement.RequestKey == Runtime.Target and Movement.Hold == true
    local nearLocked = lockedOn and distance <= 12
    if (nearLocked or weaponType == "Gun") and Config.CameraAim then
        Combat:SetCameraTarget(targetHitPart or targetRoot)
    end
    if weaponType ~= "Gun" and not nearLocked and distance > 12 then
        if Config.AutoSkills and CombatSkillService and os.clock() >= Combat.SwingUntil then
            casting = CombatSkillService:Step(entry, targetHitPart or targetRoot)
        end
        state(casting and "ATTACK" or "TRAVEL_TO_TARGET", q.Target)
        Runtime.M1Status = string.format("Approaching locked target · %.1f studs", distance)
        return
    end

    state("ATTACK", (finishing and "Mastery finish · " or "") .. q.Target)
    if weaponType == "Melee" then
        -- Keep v1.4.8 Combat:Attack untouched. It is the M1 path confirmed to work.
        -- After four successful native/input M1 requests, allow one skill attempt, then
        -- immediately return to M1. A skill can no longer run before the basic chain.
        if Combat.ComboPendingSkill then
            if Config.AutoSkills and CombatSkillService and os.clock() >= Combat.SwingUntil then
                local beforeCast = CombatSkillService.LastCastAt
                casting = CombatSkillService:Step(entry, targetHitPart or targetRoot)
                if CombatSkillService.LastCastAt > beforeCast then
                    Runtime.M1Status = "4 M1s complete · skill inserted"
                end
                Combat.ComboCount, Combat.ComboPendingSkill = 0, false
            elseif not Config.AutoSkills then
                Combat.ComboCount, Combat.ComboPendingSkill = 0, false
            end
        end

        if not casting and not Combat.ComboPendingSkill then
            local fired = Combat:Attack(entry, targetRoot, targetHitPart or targetRoot)
            if fired then
                Combat.ComboCount += 1
                Runtime.M1Status = string.format("M1 requested · combo %d/4", math.min(Combat.ComboCount, 4))
                if Combat.ComboCount >= 4 then Combat.ComboPendingSkill = true end
            end
        end
    else
        if Config.AutoSkills and CombatSkillService and os.clock() >= Combat.SwingUntil then
            casting = CombatSkillService:Step(entry, targetHitPart or targetRoot)
        end
        if not casting then Combat:Attack(entry, targetRoot, targetHitPart or targetRoot) end
    end
    if os.clock() - self.DamageAt > (q.Boss and 35 or 20) then
        if EnemyService:IsOurs(Runtime.Target) then
            Combat:Stop(); Movement:Cancel("Retry engaged target")
            self.DamageAt = os.clock()
            state("RETRY_ENGAGED", "No recent damage · retrying the same " .. q.Target)
        else
            self:Recover("No damage to " .. q.Target .. "; check range, weapon, or boss invulnerability", true)
        end
    end
end

-- PuckUI owns all flags, profiles, scaling, input binds, and minimize/restore.
local Controls = {}
Runtime.Controls = Controls
local function toggle(tab, key, name, sessionOnly)
    Controls[key] = tab:CreateToggle({Name = name, CurrentValue = Config[key], Flag = "BF_" .. key, NoConfig = sessionOnly == true,
        Callback = function(v)
            Config[key] = v == true
            if key == "AutoLevel" or key == "AutoBoss" or key == "AutoEnemy" then
                release("Farm switch changed")
                Runtime.Owner = nil
                if Runtime.Ready then notify(name .. (Config[key] and " enabled" or " stopped")) end
            elseif key == "BossQuest" then release("Boss quest option changed")
            elseif key == "NoCollision" then Movement:Cancel("Collision setting changed")
            elseif key == "CameraAim" and not Config.CameraAim then Combat:Stop()
            elseif key == "AutoDodge" and DodgeService then
                if Config.AutoDodge then Runtime.DodgeStatus = "Watching" else DodgeService:Clear("Off") end
            elseif key == "HideOwnNameplate" or key == "HidePlayerList" then if PrivacyService then PrivacyService:Step() end
            elseif key == "AutoSmallServer" and Config.AutoSmallServer then ServerService.Next = 0
            elseif key == "AutoRandomFruit" then FruitGachaService.Next = 0
            elseif key == "AutoBuyStockFruit" then FruitShopService.Next = 0
            elseif key == "AutoBuyWeapon" then PurchaseService.NextWeapon = 0
            elseif key == "AutoBuyStyle" then PurchaseService.NextStyle = 0
            elseif key == "AutoBuyHaki" then PurchaseService.NextHaki = 0
            elseif key == "AutoCollectSpawnedFruits" and FruitPickupService then FruitPickupService:Bind(); FruitPickupService.Current = nil
            elseif key == "AutoSkills" and not Config.AutoSkills and CombatSkillService then CombatSkillService.BusyUntil = 0 end
        end})
    return Controls[key]
end
local function dropdown(tab, key, name, options)
    Controls[key] = tab:CreateDropdown({Name = name, Options = options, CurrentOption = {Config[key]}, Flag = "BF_" .. key,
        Callback = function(v)
            Config[key] = type(v) == "table" and v[1] or v
            if key == "Boss" or key == "Enemy" or key == "Movement" or key == "Weapon" or key == "WeaponMode" or key == "MasteryWeapon" then release("Selection changed") end
            if key == "FruitDealer" and FruitShopService then FruitShopService.Next = 0; FruitShopService.Stock = {}; FruitShopService.Display = {}; FruitShopService.DisplayToInternal = {} end
        end})
    return Controls[key]
end
local function slider(tab, key, name, min, max, increment, suffix)
    Controls[key] = tab:CreateSlider({Name = name, Range = {min, max}, Increment = increment or 1,
        Suffix = suffix or "", CurrentValue = Config[key], Flag = "BF_" .. key, Callback = function(v) Config[key] = v end})
end
local function input(tab, key, name, placeholder, sessionOnly)
    Controls[key] = tab:CreateInput({Name = name, CurrentValue = tostring(Config[key] or ""), PlaceholderText = placeholder or "",
        Flag = "BF_" .. key, NoConfig = sessionOnly == true, Callback = function(v) Config[key] = tostring(v or "") end})
    return Controls[key]
end
local function stopAll()
    for _, key in ipairs({"AutoLevel", "AutoBoss", "AutoEnemy", "AutoStats", "AutoAura", "AutoDodge", "AutoSkills", "AutoCollectSpawnedFruits", "AutoStoreSpawnedFruits", "AutoSmallServer", "AutoRandomFruit", "AutoBuyStockFruit", "AutoBuyWeapon", "AutoBuyStyle", "AutoBuyHaki"}) do
        Config[key] = false
        if Controls[key] then Controls[key]:Set(false) end
    end
    release("Stopped by user"); Runtime.Owner = nil; state("IDLE", "Stopped")
end
local function refreshDropdown(control, key, options)
    if not control then return end
    -- PuckUI.Refresh silently changes the selected value without invoking Callback.
    -- Keep saved choices available during respawn/backpack replication.
    if Config[key] and not table.find(options, Config[key]) then table.insert(options, Config[key]) end
    local signature = table.concat(options, "\0")
    if control._BFOptionsSignature ~= signature then
        control._BFOptionsSignature = signature
        control:Refresh(options)
    end
end
local function refreshChoices()
    WeaponService.Dirty = true; WeaponService:Refresh()
    local weapons = {"Auto"}; local mastery = {"Select weapon"}; local seen = {}
    for _, entry in ipairs(WeaponService.List) do
        if not seen[entry.Tool.Name] then
            seen[entry.Tool.Name] = true; table.insert(weapons, entry.Tool.Name); table.insert(mastery, entry.Tool.Name)
        end
    end
    refreshDropdown(Controls.Weapon, "Weapon", weapons)
    refreshDropdown(Controls.MasteryWeapon, "MasteryWeapon", mastery)
    local bosses, enemies, seenB, seenE = {"Auto available"}, {"Select enemy"}, {}, {}
    for _, q in ipairs(QuestService.Records) do
        if q.Boss then if not seenB[q.Target] then table.insert(bosses, q.Target); seenB[q.Target] = true end
        elseif not seenE[q.Target] then table.insert(enemies, q.Target); seenE[q.Target] = true end
    end
    for name in pairs(EnemyService.SpawnPoints) do if not seenE[name] then table.insert(enemies, name); seenE[name] = true end end
    for m in pairs(EnemyService.Models) do
        if m:GetAttribute("IsBoss") == true and not seenB[normalize(m.Name)] then table.insert(bosses, normalize(m.Name)); seenB[normalize(m.Name)] = true end
    end
    table.sort(bosses); table.sort(enemies)
    refreshDropdown(Controls.Boss, "Boss", bosses); refreshDropdown(Controls.Enemy, "Enemy", enemies)
    if FruitShopService and #FruitShopService.Display > 0 then
        local fruits = {"Select fruit"}; for _, name in ipairs(FruitShopService.Display) do table.insert(fruits, name) end
        refreshDropdown(Controls.StockFruit, "StockFruit", fruits)
    end
end
local function buildUI()
    assert(type(loadstring) == "function", "This environment cannot compile the bundled PuckUI (loadstring is missing)")
    local compile, err = loadstring(BUNDLED_PUCKUI, "PuckUI_v3_8_0")
    assert(compile, err)
    UI = compile()
    assert(type(UI) == "table" and type(UI.CreateWindow) == "function", "PuckUI failed to initialize")
    local window = UI:CreateWindow({Name = "PuckAFK Hub | Blox Fruits", Title = "PuckAFK Hub | Blox Fruits",
        GuiName = "PuckAFK_BloxFruits", ConfigId = "BloxFruits", Width = 620, Height = 600})
    Runtime.Window = window
    window:SetCloseCallback(function() Runtime:Shutdown("Window closed") end)
    connect(window.ScreenGui.Destroying, function() Runtime:Shutdown("UI destroyed") end)

    -- Fewer top-level tabs. Advanced/manual controls live in collapsible sections.
    local home = window:CreateTab("Home")
    local farm = window:CreateTab("Farm")
    local progress = window:CreateTab("Progress")
    local fruits = window:CreateTab("Fruits")
    local utility = window:CreateTab("Utility")
    local settings = window:CreateTab("Settings")

    home:CreateSection("Status")
    Runtime.StatusLabel = home:CreateParagraph({Title = "Blox Fruits · " .. VERSION, Content = "Reading game state…"})
    home:CreateButton({Name = "Stop everything", Callback = stopAll})

    home:CreateSection("Start here")
    home:CreateParagraph({Title = "Recommended", Content = "1. Farm → Auto Level\n2. Progress → optional stats / weapon / style upgrades\nEverything else can stay at its defaults."})
    home:CreateButton({Name = "Open Farm", Callback = function() window:SelectTab(farm) end})
    home:CreateButton({Name = "Open Fruits", Callback = function() window:SelectTab(fruits) end})

    -- FARM -----------------------------------------------------------------
    farm:CreateSection("Main farm")
    toggle(farm, "AutoLevel", "Auto Level", true)
    Runtime.FarmLabel = farm:CreateLabel("Status: loading")
    dropdown(farm, "WeaponMode", "Use", {"Auto", "Equipped", "Melee", "Sword", "Gun", "Fruit"})
    dropdown(farm, "Weapon", "Weapon", {"Auto"})
    farm:CreateButton({Name = "Refresh weapons", Callback = refreshChoices})

    farm:CreateSection("Target mode")
    toggle(farm, "AutoBoss", "Farm bosses", true)
    dropdown(farm, "Boss", "Boss", {"Auto available"})
    toggle(farm, "BossQuest", "Use boss quest when available")
    toggle(farm, "RepeatBoss", "Repeat boss")
    toggle(farm, "AutoEnemy", "Farm one enemy type", true)
    dropdown(farm, "Enemy", "Enemy", {"Select enemy"})
    farm:CreateButton({Name = "Refresh targets", Callback = refreshChoices})
    farm:CreateLabel("Priority: Boss → Enemy → Auto Level")

    farm:CreateSection("Position")
    dropdown(farm, "Position", "Style", {"Behind", "Above", "Below", "Front", "Side", "Orbit", "Custom Offset"})
    slider(farm, "Distance", "Distance", 1, 40, 0.5, " studs")
    slider(farm, "Height", "Height", -25, 25, 0.5, " studs")
    slider(farm, "Side", "Side", -25, 25, 0.5, " studs")
    toggle(farm, "AboveLookDown", "Look down while Above")
    slider(farm, "AboveLookDownAngle", "Look-down angle", 0, 75, 5, "°")

    farm:CreateSection("Combat")
    slider(farm, "AttackInterval", "M1 interval", 0.15, 1, 0.05, "s")
    toggle(farm, "AutoAura", "Auto Aura", true)
    toggle(farm, "CameraAim", "Lock camera to target")
    toggle(farm, "AutoDodge", "Auto Dodge attacks")
    farm:CreateLabel("M1 stays unchanged · dodge briefly sidesteps attack wind-ups")

    farm:CreateSection("Movement · advanced", true)
    dropdown(farm, "Movement", "Travel", {"Smooth", "Walk"})
    slider(farm, "Speed", "Smooth speed", 25, 250, 5, " studs/s")
    toggle(farm, "NoCollision", "Pass through obstacles")
    slider(farm, "OrbitRadius", "Orbit radius", 2, 35, 0.5, " studs")
    slider(farm, "OrbitSpeed", "Orbit speed", 5, 120, 5, " degrees/s")

    farm:CreateSection("Skills · advanced", true)
    toggle(farm, "AutoSkills", "Use unlocked abilities")
    toggle(farm, "SkillZ", "Z")
    toggle(farm, "SkillX", "X")
    toggle(farm, "SkillC", "C")
    toggle(farm, "SkillV", "V")
    toggle(farm, "SkillF", "F")
    toggle(farm, "SkillAim", "Aim abilities at target")
    slider(farm, "SkillHold", "Key hold", 0.05, 1.5, 0.05, "s")
    slider(farm, "SkillMaxRange", "Skill range", 10, 150, 5, " studs")

    farm:CreateSection("Target rules · advanced", true)
    toggle(farm, "AvoidContested", "Avoid contested enemies")
    slider(farm, "ContestedSeconds", "Other-player damage window", 2, 12, 1, "s")
    toggle(farm, "Mastery", "Mastery finishing")
    dropdown(farm, "MasteryWeapon", "Finishing weapon", {"Select weapon"})
    slider(farm, "FinishPercent", "Switch below HP", 5, 80, 5, "%")

    -- PROGRESS -------------------------------------------------------------
    progress:CreateSection("Stats")
    toggle(progress, "AutoStats", "Auto Stats", true)
    toggle(progress, "StatMelee", "Melee")
    toggle(progress, "StatDefense", "Defense")
    toggle(progress, "StatSword", "Sword")
    toggle(progress, "StatGun", "Gun")
    toggle(progress, "StatFruit", "Blox Fruit")
    slider(progress, "StatBatch", "Points each time", 1, 25, 1)
    dropdown(progress, "StatDistribution", "Distribution", {"Lowest stat", "Round robin"})

    progress:CreateSection("Weapons & styles")
    dropdown(progress, "ShopWeapon", "Weapon to buy", SHOP_WEAPONS)
    toggle(progress, "AutoBuyWeapon", "Auto buy weapon when eligible", true)
    progress:CreateButton({Name = "Buy weapon now", Callback = function() PurchaseService.NextWeapon = 0; PurchaseService:BuyWeapon(true) end})
    progress:CreateDivider()
    dropdown(progress, "FightingStyle", "Fighting style", STYLE_NAMES)
    toggle(progress, "AutoBuyStyle", "Auto buy style when eligible", true)
    progress:CreateButton({Name = "Buy style now", Callback = function() PurchaseService.NextStyle = 0; PurchaseService:BuyStyle(true) end})
    Runtime.PurchaseLabel = progress:CreateParagraph({Title = "Purchase status", Content = "Idle"})

    progress:CreateSection("Haki & abilities")
    dropdown(progress, "HakiAbility", "Ability", HAKI_NAMES)
    toggle(progress, "AutoBuyHaki", "Auto buy when eligible", true)
    progress:CreateButton({Name = "Buy selected ability now", Callback = function() PurchaseService.NextHaki = 0; PurchaseService:BuyHaki(true) end})
    progress:CreateLabel("Teacher travel and normal prerequisites are respected")

    -- FRUITS ---------------------------------------------------------------
    fruits:CreateSection("World fruits")
    toggle(fruits, "AutoCollectSpawnedFruits", "Collect naturally spawned fruits")
    toggle(fruits, "AutoStoreSpawnedFruits", "Store after pickup")
    Runtime.FruitPickupLabel = fruits:CreateParagraph({Title = "World fruit", Content = "No natural fruit detected"})

    fruits:CreateSection("Zioles")
    toggle(fruits, "AutoRandomFruit", "Auto roll when ready", true)
    slider(fruits, "FruitMoneyReserve", "Keep Beli", 0, 10000000, 50000, " Beli")
    fruits:CreateButton({Name = "Roll now", Callback = function() FruitGachaService.Next = 0; FruitGachaService:TryRoll(true) end})
    Runtime.GachaLabel = fruits:CreateParagraph({Title = "Zioles", Content = "Not checked yet"})

    fruits:CreateSection("Fruit dealer", true)
    dropdown(fruits, "FruitDealer", "Dealer", {"Normal", "Advanced"})
    dropdown(fruits, "StockFruit", "Fruit", {"Select fruit"})
    dropdown(fruits, "DragonType", "Dragon type", {"East", "West"})
    toggle(fruits, "AutoBuyStockFruit", "Auto buy when in stock", true)
    fruits:CreateButton({Name = "Refresh stock", Callback = function() FruitShopService.Next = 0; FruitShopService:Refresh(true) end})
    fruits:CreateButton({Name = "Buy selected fruit", Callback = function() FruitShopService:BuySelected(true) end})
    Runtime.FruitShopLabel = fruits:CreateParagraph({Title = "Dealer", Content = "Stock has not been checked"})

    -- UTILITY --------------------------------------------------------------
    utility:CreateSection("Server finder")
    toggle(utility, "AutoSmallServer", "Auto find smaller servers", true)
    slider(utility, "MaxOtherPlayers", "Max other players", 0, 20, 1)
    input(utility, "ExemptFriend", "Ignore one friend", "username / display name / user ID")
    utility:CreateButton({Name = "Find smaller server now", Callback = function() ServerService.Next = 0; ServerService:FindAndHop(true) end})
    Runtime.ServerLabel = utility:CreateParagraph({Title = "Server", Content = "Checking population…"})

    utility:CreateSection("Privacy · local only", true)
    toggle(utility, "HideOwnNameplate", "Hide my overhead name", true)
    toggle(utility, "HidePlayerList", "Hide Roblox player list", true)
    utility:CreateLabel("Only changes what you see locally")

    utility:CreateSection("Session")
    toggle(utility, "AntiAFK", "Anti-AFK")
    utility:CreateButton({Name = "Rejoin", Callback = function()
        ServerService:QueueSelf()
        stopAll()
        worker("Rejoin", function() TeleportService:Teleport(game.PlaceId, Player) end)
    end})
    utility:CreateLabel("Sea detection and self-queue behavior are unchanged")

    -- SETTINGS -------------------------------------------------------------
    settings:CreateSection("Script")
    settings:CreateParagraph({Title = "Saved settings", Content = "PuckUI keeps safe selections and limits. Farm, spending and server-hop automation still starts OFF where configured."})
    settings:CreateButton({Name = "Unload Blox Fruits", Callback = function() Runtime:Shutdown("User unloaded") end})

    settings:CreateSection("Diagnostics", true)
    toggle(settings, "Debug", "Debug logging")
    Runtime.DiagnosticsLabel = settings:CreateParagraph({Title = "Runtime", Content = "Loading…"})
    settings:CreateButton({Name = "Retry discovery", Callback = function()
        EnemyService.Blocked = {}; QuestService.Failures = {}; QuestService.Dirty = true
        WorldService.Next = 0; Controller.RecoveryCount = 0; Runtime.PauseUntil = 0
        release("Manual discovery retry")
        for key, names in pairs({LiveQuests={"Quests"},Guide={"GuideModule"},GuideData={"GuideModule","GuideData"},Combat={"Controllers","CombatController"},CombatUtil={"Modules","CombatUtil"},Realm={"Util","Realm"}}) do
            if not Runtime.Modules[key] then loadModule(key,names) end
        end
    end})
    settings:CreateButton({Name = "Copy diagnostic report", Callback = function()
        local text = Runtime:DiagnosticText()
        if type(setclipboard) == "function" then setclipboard(text); notify("Diagnostics copied") else print(text); notify("Clipboard unavailable; diagnostics printed to console") end
    end})
end
function Runtime:DiagnosticText()
    local _, _, r = char()
    local h, targetRoot = EnemyService:Parts(self.Target)
    local data = Player:FindFirstChild("Data")
    local names = {}; for key in pairs(self.Modules) do table.insert(names,key) end; table.sort(names)
    local lines = {
        "PuckAFK Blox Fruits " .. VERSION, "Place: " .. tostring(game.PlaceId) .. " | Version: " .. tostring(game.PlaceVersion),
        "State: " .. self.State .. " | " .. self.Detail,
        "Sea: " .. tostring(self.Sea) .. " (" .. tostring(self.SeaSource) .. ") | Level: " .. tostring(value(data,"Level","?")),
        "Quest: " .. (self.Quest and (self.Quest.Key or self.Quest.Target) or "None"),
        "Target: " .. (self.Target and self.Target.Name or "None") .. " | HP: " .. (h and math.floor(h.Health) or "?"),
        "Distance: " .. (r and targetRoot and string.format("%.1f", (r.Position-targetRoot.Position).Magnitude) or "?") .. " | Weapon: " .. tostring(self.Weapon or "None"),
        "Combat: " .. tostring(self.CombatPath or "Idle") .. " | M1: " .. tostring(self.M1Status or "Waiting") .. " | Dodge: " .. tostring(self.DodgeStatus or "Watching"),
        "Movement: " .. (Movement.Connection and Config.Movement or "Stopped") .. " | Owner: " .. tostring(self.Owner),
        "Recovery: " .. self.LastRecovery, "Last error: " .. self.LastError,
        "Farm time: " .. math.floor(self.FarmSeconds) .. "s | Quest completions observed: " .. self.Counters.Quests,
        "Fruits collected: " .. tostring(self.Counters.FruitsCollected) .. " | Fruit pickup: " .. tostring(self.FruitPickupStatus),
        "Target claim: " .. (self.Target and (EnemyService:IsOurs(self.Target) and "ours" or EnemyService:IsContested(self.Target) and "contested" or "free") or "none"),
        "Modules: " .. table.concat(names, ", ") .. " | Quests: bundled | Combat fallback: " .. tostring(not (Runtime.Modules.Combat and Runtime.Modules.CombatUtil)), "CommF calls: " .. RemoteService.Count,
        "Server: " .. self.ServerStatus, "Gacha: " .. self.GachaStatus, "Fruit shop: " .. self.FruitShopStatus, "Purchase: " .. self.PurchaseStatus,
        "Fruit rolls: " .. self.Counters.FruitRolls .. " | Map fruits: " .. self.Counters.FruitsCollected .. " | Purchases: " .. self.Counters.Purchases .. " | Server hops: " .. self.Counters.ServerHops,
    }
    for _, item in ipairs(self.Logs) do table.insert(lines, "[" .. item.Time .. "s] " .. item.Kind .. " " .. item.Message) end
    return table.concat(lines,"\n")
end
local okUI, errorUI = xpcall(buildUI, debug.traceback)
if not okUI then log("Error", errorUI); Runtime:Shutdown("UI initialization failed"); warn("PuckAFK: " .. tostring(errorUI)); return end
QuestService:SyncActive(true)
for key, names in pairs({LiveQuests={"Quests"},Guide={"GuideModule"},GuideData={"GuideModule","GuideData"},Combat={"Controllers","CombatController"},CombatUtil={"Modules","CombatUtil"},Realm={"Util","Realm"}}) do loadModule(key,names) end
local antiAFKFailed = false
connect(Player.Idled, function()
    if not Runtime.Running or not Config.AntiAFK or antiAFKFailed or UIS:GetFocusedTextBox() then return end
    local ok, err = pcall(function()
        -- A single paired right-button pulse only when Roblox raises Idled.
        local camera = workspace.CurrentCamera
        if not camera then return end
        local virtual = game:GetService("VirtualUser")
        virtual:CaptureController()
        virtual:Button2Down(Vector2.zero, camera.CFrame)
        virtual:Button2Up(Vector2.zero, camera.CFrame)
    end)
    if not ok then antiAFKFailed = true; log("Error", "Anti-AFK unavailable: " .. tostring(err)); notify("This executor could not run Anti-AFK") end
end)
connect(Player.CharacterRemoving, function()
    release("Character removed"); WeaponService.Dirty = true
    if CombatSkillService then CombatSkillService.BusyUntil = 0; CombatSkillService.LegacyCache = setmetatable({}, {__mode = "k"}); CombatSkillService.LegacyRetry = setmetatable({}, {__mode = "k"}) end
    if FruitPickupService then FruitPickupService.Current = nil; FruitPickupService.PendingStore = nil end
    state("WAIT_CHARACTER", "Waiting for respawn")
end)
connect(Player.CharacterAdded, function()
    release("Character respawned"); WeaponService.Dirty = true; Runtime.PauseUntil = os.clock() + 1
    state("VALIDATE_PLAYER", "Waiting for character initialization")
    task.defer(function()
        task.wait(0.5)
        if Runtime.Running and PrivacyService then PrivacyService:Step() end
    end)
end)
connect(Player.OnTeleport, function(teleportState)
    if teleportState == Enum.TeleportState.Started or teleportState == Enum.TeleportState.InProgress then
        stopAll(); state("WORLD_TRANSITION", "Teleporting; execute the script again after arrival")
    elseif teleportState == Enum.TeleportState.Failed then state("IDLE", "Teleport failed; farm switches are off") end
end)
local questEventBound = false
local nextUI, nextChoices, lastTick, nextOptional, nextModuleRetry = 0, 0, os.clock(), 0, os.clock() + 5
Runtime.Ready = true
PrivacyService:Step(); ServerService.Next = 0; FruitShopService.Next = 0; FruitPickupService:Bind()
notify("Loaded. Auto Level core is ready. Item-NPC / gear automation has been removed.")
Runtime.Loop = task.defer(function()
    while Runtime.Running do
        local now = os.clock()
        if selectedOwner() and char() then Runtime.FarmSeconds = Runtime.FarmSeconds + math.min(1, now - lastTick) end
        lastTick = now
        local success, err = xpcall(function()
            WorldService:Refresh(); EnemyService:Bind(); EnemyService:UpdateDamageOwnership(); FruitPickupService:Bind()
            if now >= nextModuleRetry then
                nextModuleRetry = now + 10
                for key, names in pairs({LiveQuests={"Quests"},Guide={"GuideModule"},GuideData={"GuideModule","GuideData"},Combat={"Controllers","CombatController"},CombatUtil={"Modules","CombatUtil"},Realm={"Util","Realm"}}) do
                    if not Runtime.Modules[key] and not Runtime.Workers["Module:" .. key] then loadModule(key,names) end
                end
            end
            if not questEventBound then
                local event = path(RS, "Remotes", "QuestUpdate")
                if event and event:IsA("RemoteEvent") then
                    questEventBound = true
                    connect(event.OnClientEvent, function(active, context)
                        Runtime.ActiveQuest = active
                        Runtime.ActiveQuestKnown = true
                        QuestService.PendingUntil = 0
                        QuestService.PendingQuest = nil
                        if context and context.Context == "Complete" then
                            Runtime.Counters.Quests = Runtime.Counters.Quests + 1
                            if Runtime.Owner == "Boss" and Runtime.Quest and Runtime.Quest.Id == context.InternalQuestName and not Config.RepeatBoss then
                                Controls.AutoBoss:Set(false); notify("Boss quest completed; Boss Farm stopped")
                            end
                        end
                        Runtime.ProgressAt = os.clock()
                        if Runtime.Owner ~= "Enemy" and (not active or Runtime.Quest and not QuestService:Matches(active, Runtime.Quest)) then
                            local engaged = Runtime.Target and EnemyService:IsOurs(Runtime.Target) and EnemyService:Parts(Runtime.Target) ~= nil
                            if not engaged then
                                Movement:Cancel("Quest changed"); Combat:Stop(); Runtime.Target = nil
                                if not active then Runtime.Quest = nil end
                            else
                                log("Combat", "Quest changed while target is engaged; finishing current target first")
                            end
                        end
                    end)
                end
            end
            Controller:Step()
            if now >= nextOptional then
                nextOptional = now + 1
                if char() then AuraService:Step(); StatService:Step(); PrivacyService:Step() end
                ServerService:Step(); FruitGachaService:Step(); FruitShopService:Step(); PurchaseService:Step()
            end
            if now >= nextChoices then
                nextChoices = now + 5
                QuestService:Build(); refreshChoices()
            end
            if now >= nextUI then
                nextUI = now + 0.5
                local data = Player:FindFirstChild("Data")
                local sea = Runtime.Sea or "Detecting"
                Runtime.StatusLabel:Set({Title = Runtime.State:gsub("_", " "), Content = Runtime.Detail .. "\n" .. sea .. " · Level " .. tostring(value(data,"Level","?")) .. " · " .. math.floor(Runtime.FarmSeconds/60) .. "m farming\nQuest: " .. (Runtime.Quest and (Runtime.Quest.Name or Runtime.Quest.Target) or "None") .. "\nWeapon: " .. tostring(Runtime.Weapon or "None")})
                Runtime.FarmLabel:Set(Runtime.Detail)
                if Runtime.ServerLabel then Runtime.ServerLabel:Set({Title = "Population", Content = Runtime.ServerStatus}) end
                if Runtime.GachaLabel then Runtime.GachaLabel:Set({Title = "Zioles", Content = Runtime.GachaStatus .. "\nBeli: $" .. tostring(beli())}) end
                if Runtime.FruitShopLabel then Runtime.FruitShopLabel:Set({Title = "Fruit dealer", Content = Runtime.FruitShopStatus}) end
                if Runtime.FruitPickupLabel then Runtime.FruitPickupLabel:Set({Title = "Map fruit", Content = Runtime.FruitPickupStatus .. "\nCollected this session: " .. tostring(Runtime.Counters.FruitsCollected)}) end
                if Runtime.PurchaseLabel then Runtime.PurchaseLabel:Set({Title = "Purchases", Content = Runtime.PurchaseStatus}) end
                local targetClaim = Runtime.Target and (EnemyService:IsOurs(Runtime.Target) and "Ours" or EnemyService:IsContested(Runtime.Target) and "Contested" or "Free") or "None"
                Runtime.DiagnosticsLabel:Set({Title = "Runtime", Content = "State: " .. Runtime.State .. "\nSea: " .. sea .. "\nTarget: " .. (Runtime.Target and Runtime.Target.Name or "None") .. " · " .. targetClaim .. "\nCombat: " .. tostring(Runtime.CombatPath or "Idle") .. "\nM1: " .. tostring(Runtime.M1Status or "Waiting") .. "\nCamera: " .. tostring(Runtime.CameraStatus or "Idle") .. "\nDodge: " .. tostring(Runtime.DodgeStatus or "Watching") .. "\nPosition: " .. tostring(Runtime.PositionStatus or Config.Position) .. "\nMovement: " .. (Movement.Connection and (Movement.EffectiveMode or Config.Movement) or "Stopped") .. "\nFruit: " .. Runtime.FruitPickupStatus .. "\nServer: " .. Runtime.ServerStatus .. "\nRecovery: " .. Runtime.LastRecovery .. "\nError: " .. Runtime.LastError})
            end
            -- Same scheduler owns the watchdog; no competing recovery loop.
            if Runtime.State == "EQUIP_WEAPON" and now - Runtime.StateSince > 15 then Controller:Recover("Weapon never finished equipping", false) end
        end, debug.traceback)
        if not success then
            log("Error", err); Controller:Recover("Controller error; inspect Diagnostics", false)
        end
        task.wait(selectedOwner() and 0.2 or 0.5)
    end
end)
return Runtime

]========]
local __PUCK_ENV = _G
if type(getgenv) == "function" then
    local ok, env = pcall(getgenv)
    if ok and type(env) == "table" then __PUCK_ENV = env end
end
__PUCK_ENV.__PUCKAFK_BLOXFRUITS_SELF_SOURCE = __PUCK_SOURCE
assert(type(loadstring) == "function", "PuckAFK Blox Fruits requires loadstring")
local __PUCK_RUN, __PUCK_ERR = loadstring(__PUCK_SOURCE, "PuckAFK_BloxFruits_v1.6.8")
if not __PUCK_RUN then error(__PUCK_ERR) end
return __PUCK_RUN()
