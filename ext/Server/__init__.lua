class 'BlueprintManagerServer'

function string:split(sep)
	local sep, fields = sep or ":", {}
	local pattern = string.format("([^%s]+)", sep)
	self:gsub(pattern, function(c) fields[#fields+1] = c end)
	return fields
end

function BlueprintManagerServer:StringToLinearTransform(linearTransformString)
	local s_LinearTransformRaw = tostring(linearTransformString)
	local s_Split = s_LinearTransformRaw:gsub("%(", ""):gsub("%)", ""):gsub("% ", ","):split(",")

	local s_LinearTransform = LinearTransform(
		Vec3(tonumber(s_Split[1]), tonumber(s_Split[2]), tonumber(s_Split[3])),
		Vec3(tonumber(s_Split[4]), tonumber(s_Split[5]), tonumber(s_Split[6])),
		Vec3(tonumber(s_Split[7]), tonumber(s_Split[8]), tonumber(s_Split[9])),
		Vec3(tonumber(s_Split[10]),tonumber(s_Split[11]),tonumber(s_Split[12]))
	)
	return s_LinearTransform
end

--- remove this shit ^ 

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
	Events:Subscribe('BlueprintManager:MoveBlueprint', self, self.OnMoveBlueprint)

    NetEvents:Subscribe('RequestPostSpawnedObjects', self, self.OnRequestPostSpawnedObjects)
    NetEvents:Subscribe('SpawnBlueprintFromClient', self, self.OnSpawnBlueprintFromClient)
    NetEvents:Subscribe('DeleteBlueprintFromClient', self, self.OnDeleteBlueprintFromClient)
    NetEvents:Subscribe('MoveBlueprintFromClient', self, self.OnMoveBlueprintFromClient)
end

local spawnedObjectEntities = { }
local postSpawnedObjects = { }

function BlueprintManagerServer:GetNewRandomString()
	local pseudorandom = nil
	
	while(true) do
		pseudorandom = SharedUtils:GetRandom(10000000, 99999999)

		if timers[pseudorandom] == nil then
			break
		end
	end

	return tostring(pseudorandom)
end

function BlueprintManagerServer:OnRequestPostSpawnedObjects(player)
	-- print('BlueprintManagerServer: OnRequestPostSpawnedObjects() - Sending postSpawnedObjects one by one')

	if postSpawnedObjects == nil or 
	   postSpawnedObjects == { } then
		print('BlueprintManagerServer:OnRequestPostSpawnedObjects() : No objects found to spawn. This should only occur if no non-default Blueprints get spawned on the server, or everything got despawned again')
		return
    end
    
    for uniqueString, v in pairs(postSpawnedObjects) do
		NetEvents:SendTo('SpawnPostSpawnedObjects', player, uniqueString, v.partitionGuid, v.blueprintPrimaryInstanceGuid, v.transform, v.variationNameHash)
        -- print('BlueprintManagerServer: ' .. tostring(v.transform))
    end
end

function BlueprintManagerServer:OnSpawnBlueprintFromClient(player, uniqueString, partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, variationNameHash)
    -- print('BlueprintManagerServer:OnSpawnBlueprintFromClient() - player ' .. player.id .. ' spawns a blueprint')
    BlueprintManagerServer:OnSpawnBlueprint(uniqueString, partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, variationNameHash)
end

function BlueprintManagerServer:OnSpawnBlueprint(uniqueString, partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, variationNameHash)
	if partitionGuid == nil or
       blueprintPrimaryInstanceGuid == nil or
	   linearTransform == nil then
       error('BlueprintManagerServer:SpawnObjectBlueprint(partitionGuid, blueprintPrimaryInstanceGuid, linearTransform) - One or more parameters are nil')
       return
    end
	
	linearTransform = self:StringToLinearTransform(linearTransform) -- remove this when it works

    if type(uniqueString) ~= 'string' or 
       uniqueString == nil then
        uniqueString = BlueprintManagerServer:GetNewRandomString()
	end
	
	if spawnedObjectEntities[uniqueString] ~= nil then
		error('BlueprintManagerServer:SpawnObjectBlueprint() - Object with id ' .. uniqueString .. ' already existed as a spawned entity!')
		return
	end

	variationNameHash = variationNameHash or 0

	local blueprint = ResourceManager:FindInstanceByGUID(partitionGuid, blueprintPrimaryInstanceGuid)

	if blueprint == nil then
		error('BlueprintManagerServer:SpawnObjectBlueprint() couldnt find the specified instance')
		return
	end

	local objectBlueprint = nil

	if blueprint.typeInfo.name == 'VehicleBlueprint' then
		objectBlueprint = VehicleBlueprint(blueprint)
	elseif blueprint.typeInfo.name == 'ObjectBlueprint' then
		objectBlueprint = ObjectBlueprint(blueprint)
	elseif blueprint.typeInfo.name == 'EffectBlueprint' then
		objectBlueprint = EffectBlueprint(blueprint)
	else
		error('BlueprintManagerServer:SpawnObjectBlueprint() blueprint is not of any type that is supported')
		print('Actual type: ' .. blueprint.typeInfo.name)
		return
	end

	local broadcastToClient = objectBlueprint.typeInfo.name ~= 'VehicleBlueprint' --and objectBlueprint.needNetworkId == false

	-- vehicle spawns or blueprint marked with needNetworkId == true dont need to be broadcast local

	if broadcastToClient then
        NetEvents:BroadcastLocal('SpawnBlueprint', uniqueString, partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, variationNameHash)
	end

	local params = EntityCreationParams()
	params.transform = linearTransform
	params.variationNameHash = variationNameHash
	params.networked = objectBlueprint.needNetworkId == true

    local objectEntities = EntityManager:CreateServerEntitiesFromBlueprint(objectBlueprint, params)
    
	for i, entity in pairs(objectEntities) do
		entity:Init(Realm.Realm_ClientAndServer, true)
    end
    
	spawnedObjectEntities[uniqueString] = { objectEntities = objectEntities, broadcastToClient = broadcastToClient }
        
    if broadcastToClient then
		local postSpawnedObject = { partitionGuid = partitionGuid, blueprintPrimaryInstanceGuid = blueprintPrimaryInstanceGuid, transform = linearTransform, variationNameHash = variationNameHash } 
        postSpawnedObjects[uniqueString] = postSpawnedObject -- these objects will get loaded for new clients joining the game later
	end
end

function BlueprintManagerServer:OnDeleteBlueprintFromClient(player, uniqueString)
    BlueprintManagerServer:OnDeleteBlueprint(uniqueString)
end

function BlueprintManagerServer:OnDeleteBlueprint(uniqueString)
    if spawnedObjectEntities[uniqueString] ~= nil then
        for i, entity in pairs(spawnedObjectEntities[uniqueString].objectEntities) do
            if entity ~= nil then
                entity:Destroy()
            end
        end
		
		if spawnedObjectEntities[uniqueString].broadcastToClient then
        	NetEvents:BroadcastLocal('DeleteBlueprint', uniqueString)
		end

		spawnedObjectEntities[uniqueString] = nil
    else
        error('BlueprintManagerServer:OnDeleteBlueprint(uniqueString): Could not find a blueprint with the ID: ' .. uniqueString)
        return
    end

    if postSpawnedObjects[uniqueString] ~= nil then
        postSpawnedObjects[uniqueString] = nil
    end
end

function BlueprintManagerServer:OnMoveBlueprintFromClient(player, uniqueString, newLinearTransform)
	BlueprintManagerServer:OnMoveBlueprint(uniqueString, newLinearTransform)
end

function BlueprintManagerServer:OnMoveBlueprint(uniqueString, newLinearTransform)
	if spawnedObjectEntities[uniqueString] == nil then
        error('BlueprintManagerServer:OnMoveBlueprint(uniqueString, newLinearTransform): Could not find a blueprint with the ID: ' .. uniqueString)
        return
	end
	
	newLinearTransform = self:StringToLinearTransform(newLinearTransform) -- remove this when it works

	for i, l_Entity in pairs(spawnedObjectEntities[uniqueString].objectEntities) do
		local s_Entity = SpatialEntity(l_Entity)
		if s_Entity ~= nil then
			s_Entity.transform = newLinearTransform
		end
	end

	if spawnedObjectEntities[uniqueString].broadcastToClient then
		NetEvents:BroadcastLocal('MoveBlueprint', uniqueString, newLinearTransform)
	end
end

g_BlueprintManagerServer = BlueprintManagerServer()

