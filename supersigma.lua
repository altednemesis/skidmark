local modules

for _, func in getgc(false) do
    if type(func) == "function" and islclosure(func) and debug.getinfo(func).name == "require" and string.find(debug.getinfo(func).source, "ClientLoader") then
        modules = {}

        for moduleName, moduleCache in debug.getupvalue(func, 1)._cache do
            modules[moduleName] = moduleCache.module
        end

        break
    end
end

local network = modules.NetworkClient
local modifyData = modules.ModifyData
local bulletObject = modules.BulletObject
local playerDataUtils = modules.PlayerDataUtils
local contentDatabase = modules.ContentDatabase
local playerClient = modules.PlayerDataClientInterface
local weaponInterface = modules.WeaponControllerInterface

local realWeapons = {}
local fakeWeapons = {}

local classData = playerDataUtils.getClassData(playerClient.getPlayerData())
for _, class in {"Assault", "Scout", "Support", "Recon"} do
    local primary = classData[class].Primary.Name
    local secondary = classData[class].Secondary.Name

    fakeWeapons[class] = {primary, secondary}
    realWeapons[class] = {primary, secondary}
end

local newbullet = bulletObject.new
function bulletObject.new(bulletData)
    if bulletData.onplayerhit then
        local controller = weaponInterface.getActiveWeaponController()
        local data = controller:getActiveWeapon():getWeaponData()
        local displayname = data.displayname or data.name
        local name = fakeWeapons[playerDataUtils.getClassData(playerClient.getPlayerData()).curclass][controller:getActiveWeaponIndex()]

        if displayname == name then
            local serverSpeed = contentDatabase.getWeaponData(name).bulletspeed
            bulletData.velocity = bulletData.velocity.Unit * serverSpeed
        end
    end

    return newbullet(bulletData)
end

local getModifiedData = modifyData.getModifiedData
function modifyData.getModifiedData(data, ...)
    setreadonly(data, false)

    for class, weapons in fakeWeapons do
        if class == playerDataUtils.getClassData(playerClient.getPlayerData()).curclass then
            for slot, name in weapons do
                local displayname = data.displayname or data.name

                if name == displayname then
                    local realData = contentDatabase.getWeaponData(realWeapons[class][slot])
                    local firecap = realData.firecap or ((realData.variablefirerate and math.max(table.unpack(realData.firerate))) or realData.firerate)

                    if data.variablefirerate then
                        local newFireRates = {}

                        for firerateIndex, firerate in data.firerate do
                            newFireRates[firerateIndex] = math.min(firerate, firecap)
                        end

                        data.firerate = newFireRates
                    elseif data.firerate > firecap then
                        data.firerate = firecap
                    end

                    if data.firecap and data.firecap > firecap then
                        data.firecap = firecap
                    end

                    if data.magsize > realData.magsize then
                        data.magsize = realData.magsize
                        data.sparerounds = realData.sparerounds
                    else
                        data.sparerounds = (realData.magsize + realData.sparerounds) - data.magsize
                    end

                    if data.pelletcount ~= realData.pelletcount then
                        data.pelletcount = realData.pelletcount
                    end

                    if data.bulletspeed ~= realData.bulletspeed then
			            data.bulletspeed = realData.bulletspeed
                    end

                    if data.penetrationdepth > realData.penetrationdepth then
                        data.penetrationdepth = realData.penetrationdepth
                    end

                    break
                end
            end
        end
    end

    return getModifiedData(data, ...)
end

local send = network.send
function network:send(name, ...)
    if name == "changeWeapon" then
        local slot, weapon = ...
        local playerData = playerClient.getPlayerData()
        local class = playerDataUtils.getClassData(playerData).curclass
        local newPlayerData = table.clone(playerData)
        newPlayerData.unlockAll = false

        if slot == "Primary" then
            fakeWeapons[class][1] = weapon

            if playerDataUtils.ownsWeapon(newPlayerData, weapon) then
                realWeapons[class][1] = weapon
            end
        elseif slot == "Secondary" then
            fakeWeapons[class][2] = weapon

            if playerDataUtils.ownsWeapon(newPlayerData, weapon) then
                realWeapons[class][2] = weapon
            end
        end
    end

    return send(self, name, ...)
end

playerClient.getPlayerData().unlockAll = true
