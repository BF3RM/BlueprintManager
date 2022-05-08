class 'BlueprintManagerServer'
require "__shared/Logger"

local m_Logger = Logger("BlueprintManager", false)
local timers = {}
local g_InitAll = false

function string:split(sep)
	local sep, fields = sep or ":", {}
	local pattern = string.format("([^%s]+)", sep)
	self:gsub(pattern, function(c) fields[#fields+1] = c end)
	return fields
end

function BlueprintManagerServer:StringToLinearTransform(linearTransformString)
	local s_LinearTransformRaw = tostring(linearTransformString)
	local s_Split = s_LinearTransformRaw:gsub("%(", ""):gsub("%)", ""):gsub("% ", ","):split(",")

	
	if(s_Split[12] == nil) then
		error("Failed String2LinearTransform: " .. linearTransformString)
		return false
	end
	
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
	self:RegisterHooks()
end

function BlueprintManagerServer:RegisterHooks()
	Hooks:Install('EntityFactory:Create', 1, function(hook, entityData, transform)
		if g_InitAll then
			local possibleEntity = hook:Call()
			if possibleEntity ~= nil and possibleEntity:Is('Entity') then
				possibleEntity:Init(Realm.Realm_Server, true)
			end
		end
	end)
end

function BlueprintManagerServer:RegisterVars()
end

function BlueprintManagerServer:RegisterEvents()
	Events:Subscribe('Level:Destroy', self, self.OnLevelDestroyed)

	Events:Subscribe('BlueprintManager:SpawnBlueprint', self, self.OnSpawnBlueprint)
	Events:Subscribe('BlueprintManager:DeleteBlueprintByEntityId', self, self.OnDeleteBlueprintByEntityId)
	Events:Subscribe('BlueprintManager:DeleteBlueprint', self, self.OnDeleteBlueprint)
	Events:Subscribe('BlueprintManager:MoveBlueprintByEntityId', self, self.OnMoveBlueprintByEntityId)
	Events:Subscribe('BlueprintManager:MoveBlueprint', self, self.OnMoveBlueprint)
	Events:Subscribe('BlueprintManager:EnableEntityByEntityId', self, self.OnEnableEntityByEntityId)
	Events:Subscribe('BlueprintManager:EnableEntity', self, self.OnEnableEntity)

	NetEvents:Subscribe('RequestPostSpawnedObjects', self, self.OnRequestPostSpawnedObjects)
	NetEvents:Subscribe('SpawnBlueprintFromClient', self, self.OnSpawnBlueprintFromClient)
	NetEvents:Subscribe('DeleteBlueprintFromClient', self, self.OnDeleteBlueprintFromClient)
	NetEvents:Subscribe('MoveBlueprintFromClient', self, self.OnMoveBlueprintFromClient)
end

local spawnedObjectEntities = { }
local postSpawnedObjects = { }

function BlueprintManagerServer:OnLevelDestroyed()
	spawnedObjectEntities = { }
	postSpawnedObjects = { }
end

function BlueprintManagerServer:FindUniqueIdByInstanceId(instanceId)

	for uniqueId, spawnedObjectEntity in pairs(spawnedObjectEntities) do
		if spawnedObjectEntity.objectEntities ~= nil then
			for i, objectEntity in ipairs(spawnedObjectEntity.objectEntities) do
				if instanceId == objectEntity.instanceId then
					return uniqueId
				end
			end
		end
	end

	return
end

-- TODO: implement DeleteBlueprintByEntityId and MoveBlueprintByEntityId
function BlueprintManagerServer:OnEnableEntityByEntityId(instanceId, enable)

	m_Logger:Write("Server received request to enable entity with instanceId: " .. tostring(instanceId))

	if instanceId == nil then
		error("OnEnableEntityByEntityId : instanceId is null")
		return
	end

	local foundUniqueId = self:FindUniqueIdByInstanceId(instanceId)

	if foundUniqueId == nil then
		error("Couldnt find uniqueId for entityId: ".. instanceId)
	end

	self:OnEnableEntity(foundUniqueId, enable)
	
end

function BlueprintManagerServer:OnEnableEntity(uniqueId, enable)
	
	if enable then
		m_Logger:Write("Server received request to enable blueprint with uniqueId: " .. uniqueId)
	else
		m_Logger:Write("Server received request to disable blueprint with uniqueId: " .. uniqueId)
	end
	
	if uniqueId == nil then
		error("BlueprintManagerServer:OnEnableEntity() : Unique id is null")
		return
	end

	if spawnedObjectEntities[uniqueId] == nil then
		error("BlueprintManagerServer:OnEnableEntity() : Tried to enable/disable entity that isn't spawned")
		return
	end

	for i, objectEntity in ipairs(spawnedObjectEntities[uniqueId].objectEntities) do
		if enable then
			objectEntity:FireEvent("Enable")
			-- print("enabling entity ".. uniqueId)
		else
			objectEntity:FireEvent("Disable")
			-- print("disabling entity ".. uniqueId)
		end
	end

	spawnedObjectEntities[uniqueId].enabled = enable

	if postSpawnedObjects[uniqueId] ~= nil then
		postSpawnedObjects[uniqueId].enabled = enable
  	end

	-- print(spawnedObjectEntities[uniqueId].broadcastToClient)
	if spawnedObjectEntities[uniqueId].broadcastToClient then
		
		if enable then
			m_Logger:Write("Sending command to clients to enable blueprint with uniqueId: " .. uniqueId)
		else
			m_Logger:Write("Sending command to clients to disable blueprint with uniqueId: " .. uniqueId)
		end
	
		NetEvents:BroadcastLocal('EnableEntity', uniqueId, enable)
	end
end

function BlueprintManagerServer:GetNewRandomString()
	local pseudorandom = nil
	
	while(true) do
		pseudorandom = MathUtils:GetRandomInt(10000000, 99999999)

		if timers[pseudorandom] == nil then
				timers[pseudorandom] = true
			break
		end
	end

	return tostring(pseudorandom)
end

function BlueprintManagerServer:OnRequestPostSpawnedObjects(player)
	-- print('BlueprintManagerServer: OnRequestPostSpawnedObjects() - Sending postSpawnedObjects one by one')

	if postSpawnedObjects == nil or 
	   postSpawnedObjects == { } then
		-- print('BlueprintManagerServer:OnRequestPostSpawnedObjects() : No objects found to spawn. This should only occur if no non-default Blueprints get spawned on the server, or everything got despawned again')
		return
	end
	
	for uniqueString, v in pairs(postSpawnedObjects) do
		NetEvents:SendTo('SpawnPostSpawnedObjects', player, uniqueString, v.partitionGuid, v.blueprintPrimaryInstanceGuid, v.transform, v.variationNameHash, v.enabled)
		-- print('BlueprintManagerServer: ' .. tostring(v.transform))
	end
end

function BlueprintManagerServer:OnSpawnBlueprintFromClient(player, uniqueString, partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, variationNameHash)
	-- print('BlueprintManagerServer:OnSpawnBlueprintFromClient() - player ' .. player.id .. ' spawns a blueprint')
	BlueprintManagerServer:OnSpawnBlueprint(uniqueString, partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, variationNameHash)
end

function BlueprintManagerServer:OnSpawnBlueprint(uniqueString, partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, variationNameHash, serverOnly, networked, indestructable)
	
	m_Logger:Write("Server received request to spawn blueprint with guid: " .. tostring(blueprintPrimaryInstanceGuid))
	
	serverOnly = serverOnly or false
	
	if partitionGuid == nil or
	   blueprintPrimaryInstanceGuid == nil or
	   linearTransform == nil then
	   error('BlueprintManagerServer:SpawnObjectBlueprint(partitionGuid, blueprintPrimaryInstanceGuid, linearTransform) - One or more parameters are nil')
	   return
	end
	
	linearTransform = self:StringToLinearTransform(linearTransform) -- remove this when it works
	if(linearTransform == false) then
		print("Failed to move blueprint.")
		return
	end

	if type(uniqueString) ~= 'string' or 
	   uniqueString == nil then
		
		uniqueString = BlueprintManagerServer:GetNewRandomString()
	end
	
	if spawnedObjectEntities[uniqueString] ~= nil then
		error('BlueprintManagerServer:SpawnObjectBlueprint() - Object with id ' .. uniqueString .. ' already existed as a spawned entity!')
		return
	end

	variationNameHash = variationNameHash or 0

	local blueprint = ResourceManager:FindInstanceByGuid(partitionGuid, blueprintPrimaryInstanceGuid)

	if blueprint == nil then
		error('BlueprintManagerServer:SpawnObjectBlueprint() couldnt find the specified instance')
		return
	end

	local objectBlueprint = _G[blueprint.typeInfo.name](blueprint)

	-- print('BlueprintManagerServer:SpawnObjectBlueprint() blueprint type: ' .. blueprint.typeInfo.name)

	local broadcastToClient = not objectBlueprint.needNetworkId

	-- vehicle spawns or blueprint marked with needNetworkId == true dont need to be broadcast local

	if broadcastToClient and serverOnly == false then
		m_Logger:Write("Sending command to clients to spawn blueprint with guid: " .. tostring(blueprintPrimaryInstanceGuid))
		NetEvents:BroadcastLocal('SpawnBlueprint', uniqueString, partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, variationNameHash)
	end

	local params = EntityCreationParams()
	params.transform = linearTransform
	params.variationNameHash = variationNameHash

	--this is required for some blueprints because they must be in Realm.Realm_Client
	--e.g. "XP_Raw/Props/SupplyAirdrop_01/SupplyAirdrop_01_XP"
	--this may mean that the object you are spawning does not have collisions 

	if(networked == nil)then
		params.networked = objectBlueprint.needNetworkId
	else
		params.networked = networked
	end

	g_InitAll = true

	local entityBus = EntityManager:CreateEntitiesFromBlueprint(objectBlueprint, params)
	if entityBus == nil then
		--error('entityBus was nil')
		g_InitAll = false
		return
	end

	local objectEntities = entityBus.entities

	for _, entity in pairs(objectEntities) do
		entity:Init(Realm.Realm_Server, true)
		if(indestructable ~= nil and indestructable == true)then
			local s_physEnt = PhysicsEntity(entity)
			if(s_physEnt ~= nil)then
				local dmgFunc = function(ent, dmgInfo, dmgGiverInfo)
					return false
				end
				s_physEnt:RegisterDamageCallback(dmgFunc)
			end
		end
	end
	g_InitAll = false

	spawnedObjectEntities[uniqueString] = { 
		objectEntities = objectEntities, 
		partitionGuid = partitionGuid, 
		blueprintPrimaryInstanceGuid = blueprintPrimaryInstanceGuid, 
		broadcastToClient = broadcastToClient, 
		variationNameHash = variationNameHash,
		enabled = true
	}

	if broadcastToClient then
		local postSpawnedObject = 
		{ 
			partitionGuid = partitionGuid, 
			blueprintPrimaryInstanceGuid = blueprintPrimaryInstanceGuid, 
			transform = linearTransform, 
			variationNameHash = variationNameHash,
			enabled = true
		}

		postSpawnedObjects[uniqueString] = postSpawnedObject -- these objects will get loaded for new clients joining the game later
	end
end

function BlueprintManagerServer:OnDeleteBlueprintByEntityId(instanceId)

	m_Logger:Write("Server received request to spawn blueprint with instanceId: " .. tostring(instanceId))
	
	if instanceId == nil then
		error("OnDeleteBlueprintByEntityId : instanceId is null")
		return
	end

	local foundUniqueId = self:FindUniqueIdByInstanceId(instanceId)

	if foundUniqueId == nil then
		error("Couldnt find uniqueId for entityId: ".. instanceId)
	end

	self:OnDeleteBlueprint(foundUniqueId)
end

function BlueprintManagerServer:OnDeleteBlueprintFromClient(player, uniqueString)
	BlueprintManagerServer:OnDeleteBlueprint(uniqueString)
end

function BlueprintManagerServer:OnDeleteBlueprint(uniqueString, serverOnly)
	
	m_Logger:Write("Server received request to spawn blueprint with uniqueString: " .. uniqueString)
	
	if spawnedObjectEntities[uniqueString] ~= nil then
		for i, entity in pairs(spawnedObjectEntities[uniqueString].objectEntities) do
			if entity ~= nil then
				entity:Destroy()
			end
		end
		
		if spawnedObjectEntities[uniqueString].broadcastToClient and serverOnly ~= true then
			m_Logger:Write("Sending command to clients to delete blueprint with uniqueString: " .. uniqueString)
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

function BlueprintManagerServer:OnMoveBlueprintByEntityId(instanceId, newLinearTransform)

	m_Logger:Write("Server received request to move blueprint with instanceId: " .. tostring(instanceId))

	if instanceId == nil then
		error("OnMoveBlueprintByEntityId : instanceId is null")
		return
	end

	local foundUniqueId = self:FindUniqueIdByInstanceId(instanceId)

	if foundUniqueId == nil then
		error("Couldnt find uniqueId for entityId: ".. instanceId)
	end

	self:OnMoveBlueprint(foundUniqueId, newLinearTransform)
end

function BlueprintManagerServer:OnMoveBlueprint(uniqueString, newLinearTransform)
	
	m_Logger:Write("Server received request to move entity with uniqueString: " .. uniqueString)

	if spawnedObjectEntities[uniqueString] == nil then
		error('BlueprintManagerServer:OnMoveBlueprint(uniqueString, newLinearTransform): Could not find a blueprint with the ID: ' .. uniqueString)
		return
	end

	-- print("Moving [" .. uniqueString .. "]")
	
	newLinearTransform = self:StringToLinearTransform(newLinearTransform) -- remove this when it works

	--Changing the transform doesnt work on server (for now at least)
	for i, l_Entity in pairs(spawnedObjectEntities[uniqueString].objectEntities) do
		local s_Entity = SpatialEntity(l_Entity)
		if s_Entity ~= nil then
			s_Entity.transform = newLinearTransform
			s_Entity:FireEvent("Disable")
			s_Entity:FireEvent("Enable")
		end
	end

	-- Workaround:
	--local partitionGuid = spawnedObjectEntities[uniqueString].partitionGuid
	--local blueprintPrimaryInstanceGuid = spawnedObjectEntities[uniqueString].blueprintPrimaryInstanceGuid
	--local variationNameHash = spawnedObjectEntities[uniqueString].variationNameHash
	--self:OnDeleteBlueprint(uniqueString, true)
	--self:OnSpawnBlueprint(uniqueString, partitionGuid, blueprintPrimaryInstanceGuid, newLinearTransform, variationNameHash, true)
--
--
	if spawnedObjectEntities[uniqueString].broadcastToClient then
		m_Logger:Write("Sending command to clients to move blueprint with uniqueString: " .. uniqueString)
		NetEvents:BroadcastLocal('MoveBlueprint', uniqueString, newLinearTransform)
	end
--
	--if postSpawnedObjects[uniqueString] ~= nil then
	--  postSpawnedObjects[uniqueString].transform = newLinearTransform
  --end
end


g_BlueprintManagerServer = BlueprintManagerServer()

