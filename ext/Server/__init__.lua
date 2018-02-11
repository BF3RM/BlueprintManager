class 'BlueprintManagerServer'

function string:split(sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    self:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
 end

function BlueprintManagerServer:StringToLinearTransform(p_LinearTransform)
	local s_LinearTransformRaw = tostring(p_LinearTransform)
    local s_Split = s_LinearTransformRaw:gsub("%(", ""):gsub("%)", ""):gsub("% ", ","):split(",")

	local s_LinearTransform = LinearTransform(
		Vec3(tonumber(s_Split[1]), tonumber(s_Split[2]), tonumber(s_Split[3])),
		Vec3(tonumber(s_Split[4]), tonumber(s_Split[5]), tonumber(s_Split[6])),
		Vec3(tonumber(s_Split[7]), tonumber(s_Split[8]), tonumber(s_Split[9])),
		Vec3(tonumber(s_Split[10]),tonumber(s_Split[11]),tonumber(s_Split[12]))
	)
	return s_LinearTransform
end

------------------------- remove ^^^^

function BlueprintManagerServer:__init()
	print("Initializing BlueprintManagerServer")
	self:RegisterVars()
	self:RegisterEvents()
end

function BlueprintManagerServer:RegisterVars()
end

function BlueprintManagerServer:RegisterEvents()
    Events:Subscribe('BlueprintManager:SpawnBlueprint', self, self.OnSpawnBlueprint)
    Events:Subscribe('BlueprintManager:DeleteBlueprint', self, self.OnDeleteBlueprint)
	Events:Subscribe('Engine:Update', self, self.OnEngineUpdate)

    NetEvents:Subscribe('RequestPostSpawnedObjects', self, self.OnRequestPostSpawnedObjects)
    NetEvents:Subscribe('SpawnBlueprintFromClient', self, self.OnSpawnBlueprintFromClient)
    NetEvents:Subscribe('DeleteBlueprintFromClient', self, self.OnDeleteBlueprintFromClient)
end

local spawnedObjectEntities = { }
local postSpawnedObjects = { }
local lastDelta = 0
local currentTime = 0
local isRandomseedSet = false

function BlueprintManagerServer:GetNewRandomString()
    if currentTime == 0 then
        error('CurrentTime was 0, that means the OnEngineUpdate didnt start yet. No way you should be spawning stuff already.')
    end

    local pseudorandom = nil
    
    while(spawnedObjectEntities[pseudorandom] ~= nil) do
        pseudorandom = SharedUtils:GetRandom(10000000, 99999999)
    end

    return tostring(pseudorandom)
end

function BlueprintManagerServer:OnRequestPostSpawnedObjects(player)
	print('BlueprintManagerServer: OnRequestPostSpawnedObjects() - Sending postSpawnedObjects one by one')

	if postSpawnedObjects == nil or 
	   postSpawnedObjects == { } then
		print('BlueprintManagerServer:OnRequestPostSpawnedObjects() : No objects found to spawn. This should only occur if no non-default Blueprints get spawned on the server, or everything got despawned again')
		return
    end
    
    for uniqueString, v in pairs(postSpawnedObjects) do
        NetEvents:SendTo('SpawnPostSpawnedObjects', player, v.partitionGuid, v.blueprintPrimaryInstanceGuid, v.transform, uniqueString)
        -- print('BlueprintManagerServer: ' .. tostring(v.transform))
    end
end

function BlueprintManagerServer:OnDeleteBlueprintFromClient(player, uniqueString)
    print('BlueprintManagerServer:OnDeleteBlueprintFromClient() - player ' .. player.id .. ' deletes a blueprint')
    BlueprintManagerServer:OnDeleteBlueprint(uniqueString)
end

function BlueprintManagerServer:OnDeleteBlueprint(uniqueString)
    if spawnedObjectEntities[uniqueString] ~= nil then
        for i, entity in pairs(spawnedObjectEntities[uniqueString]) do
            if entity ~= nil then
                entity:Destroy()
            end
        end

        spawnedObjectEntities[uniqueString] = nil
        NetEvents:BroadcastLocal('DeleteBlueprint', uniqueString)
    else
        error('BlueprintManagerServer:OnDeleteBlueprint(uniqueString): Could not find a blueprint with the ID: ' .. uniqueString)
        return
    end

    if postSpawnedObjects[uniqueString] ~= nil then
        for i, entity in pairs(postSpawnedObjects[uniqueString]) do
            if entity ~= nil then
                entity:Destroy()
            end
        end

        postSpawnedObjects[uniqueString] = nil
    end
end

function BlueprintManagerServer:OnSpawnBlueprintFromClient(player, partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, uniqueString)
    print('BlueprintManagerServer:OnSpawnBlueprintFromClient() - player ' .. player.id .. ' spawns a blueprint')
    BlueprintManagerServer:OnSpawnBlueprint(partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, uniqueString)
end

function BlueprintManagerServer:OnSpawnBlueprint(partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, uniqueString)
	if partitionGuid == nil or
       blueprintPrimaryInstanceGuid == nil or
	   linearTransform == nil then
       error('BlueprintManagerServer: SpawnObjectBlueprint(partitionGuid, blueprintPrimaryInstanceGuid, linearTransform) - One or more parameters are nil')
       return
    end
    
    print(type(partitionGuid))

    linearTransform = BlueprintManagerServer:StringToLinearTransform(linearTransform) -- remove this once Event types serialization is fixed

    if type(uniqueString) ~= 'string' or 
       uniqueString == nil then
        uniqueString = BlueprintManagerServer:GetNewRandomString()
    end

	local blueprint = ResourceManager:FindInstanceByGUID(partitionGuid, blueprintPrimaryInstanceGuid)

	if blueprint == nil then
		print('BlueprintManagerServer:SpawnObjectBlueprint() couldnt find the specified instance')
		return
	end

	local objectBlueprint = nil

	if blueprint.typeName == 'VehicleBlueprint' then
		objectBlueprint = VehicleBlueprint(blueprint)
	elseif blueprint.typeName == 'ObjectBlueprint' then
		objectBlueprint = ObjectBlueprint(blueprint)
	elseif blueprint.typeName == 'EffectBlueprint' then
		objectBlueprint = EffectBlueprint(blueprint)
	else
		print('BlueprintManagerServer:SpawnObjectBlueprint() blueprint is not of any type that is supported')
		print('Actual type: ' .. blueprint.typeName)
		return
	end

	print('BlueprintManagerServer: Got spawn object event for '.. objectBlueprint.name)

	-- vehicle spawns or blueprint marked with needNetworkId == true dont need to be broadcast local
	if objectBlueprint.typeName ~= 'VehicleBlueprint' and not objectBlueprint.needNetworkId then
		print('BlueprintManagerServer: Not a VehicleBlueprint -> BroadcastLocal') -- debug only
        NetEvents:BroadcastLocal('SpawnObject', partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, uniqueString)
	end

    print(linearTransform)
    print(objectBlueprint.needNetworkId)
    local objectEntities = EntityManager:CreateServerEntitiesFromBlueprint(objectBlueprint, linearTransform, objectBlueprint.needNetworkId == true)
    
	for i, entity in pairs(objectEntities) do
		entity:Init(Realm.Realm_ClientAndServer, true)
    end
    
	spawnedObjectEntities[uniqueString] = objectEntities
        
    if objectBlueprint.typeName ~= 'VehicleBlueprint' and not objectBlueprint.needNetworkId then
		local postSpawnedObject = { partitionGuid = partitionGuid, blueprintPrimaryInstanceGuid = blueprintPrimaryInstanceGuid, transform = linearTransform } 
		print('BlueprintManagerServer: adding table to postSpawnedObjects')
        print(postSpawnedObject)
        postSpawnedObjects[uniqueString] = postSpawnedObject -- these objects will get loaded for new clients joining the game later
	end
end

g_BlueprintManagerServer = BlueprintManagerServer()

