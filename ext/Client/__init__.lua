class 'BlueprintManagerClient'
require "__shared/Logger"

local m_Logger = Logger("BlueprintManager", false)
local g_InitAll = false
local g_CurrentlySpawningBlueprint = ""

function BlueprintManagerClient:__init()
	print("Initializing BlueprintManagerClient")
	self:RegisterVars()
	self:RegisterEvents()
	self:RegisterHooks()
end

function BlueprintManagerClient:RegisterVars()
end

local spawnedObjectEntities = { }

function BlueprintManagerClient:RegisterHooks()
	Hooks:Install('EntityFactory:Create', 1, function(hook, entityData, transform)
		if g_InitAll then
			local possibleEntity = hook:Call()
			if possibleEntity ~= nil and possibleEntity:Is('Entity') then
				possibleEntity:Init(Realm.Realm_Client, true)
				possibleEntity:FireEvent("Start")

				local length = #spawnedObjectEntities[g_CurrentlySpawningBlueprint]
				spawnedObjectEntities[g_CurrentlySpawningBlueprint][length + 1] = possibleEntity
			end
		end
	end)
end

function BlueprintManagerClient:RegisterEvents()
    Events:Subscribe('Level:LoadingInfo', self, self.OnLevelLoadingInfo)
    Events:Subscribe('Level:Destroy', self, self.OnLevelDestroyed)

    Events:Subscribe('BlueprintManager:SpawnBlueprintFromClient', self, self.OnSpawnBlueprintFromClient)
    Events:Subscribe('BlueprintManager:DeleteBlueprintFromClient', self, self.OnDeleteBlueprintFromClient)
    Events:Subscribe('BlueprintManager:MoveBlueprintFromClient', self, self.OnMoveBlueprintFromClient)

    NetEvents:Subscribe('SpawnBlueprint', self, self.OnSpawnBlueprint)
    NetEvents:Subscribe('DeleteBlueprint', self, self.OnDeleteBlueprint)
    NetEvents:Subscribe('MoveBlueprint', self, self.OnMoveBlueprint)
    NetEvents:Subscribe('SpawnPostSpawnedObjects', self, self.OnSpawnPostSpawnedObject)
    NetEvents:Subscribe('EnableEntity', self, self.OnEnableEntity)
end

function BlueprintManagerClient:OnLevelDestroyed()
	spawnedObjectEntities = { }
end

function BlueprintManagerClient:OnEnableEntity(uniqueString, enable)
	
	if enable then
		m_Logger:Write("Client received request to enable blueprint with uniqueString: " .. uniqueString)
	else
		m_Logger:Write("Client received request to disable blueprint with uniqueString: " .. uniqueString)
	end
	
	if spawnedObjectEntities[uniqueString] == nil then
		error('Tring to enable/disable an entity that doesnt exist!')
		return
	end

	for i, objectEntity in pairs(spawnedObjectEntities[uniqueString]) do
		if enable then
			objectEntity:FireEvent("Enable")
			-- print("enabling entity ".. uniqueString)
		else
			objectEntity:FireEvent("Disable")
			-- print("disabling entity ".. uniqueString)
		end
	end
end


function BlueprintManagerClient:OnSpawnBlueprintFromClient(uniqueString, partitionGuid, blueprintPrimaryInstance, linearTransform, variationNameHash)
    NetEvents:SendLocal('SpawnBlueprintFromClient', uniqueString, partitionGuid, blueprintPrimaryInstance, linearTransform, variationNameHash)
end

function BlueprintManagerClient:OnDeleteBlueprintFromClient(uniqueString)
    NetEvents:SendLocal('DeleteBlueprintFromClient', uniqueString)
end

function BlueprintManagerClient:OnMoveBlueprintFromClient(uniqueString, newLinearTransform)
    NetEvents:SendLocal('MoveBlueprintFromClient', uniqueString, newLinearTransform)
end

function BlueprintManagerClient:OnSpawnBlueprint(uniqueString, partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, variationNameHash) -- this should only be called via NetEvents
	
	m_Logger:Write("Client received request to spawn blueprint with guid: " .. tostring(blueprintPrimaryInstanceGuid))
	
	if partitionGuid == nil or
	blueprintPrimaryInstanceGuid == nil or
	   linearTransform == nil then
	    error('BlueprintManagerClient: SpawnObjectBlueprint(partitionGuid, blueprintPrimaryInstanceGuid, linearTransform) - One or more parameters are nil')
	end

	if spawnedObjectEntities[uniqueString] ~= nil then
		error('Object with id ' .. uniqueString .. ' already existed as a spawned entity!')
		return
	end

	variationNameHash = variationNameHash or 0

    local blueprint = ResourceManager:FindInstanceByGuid(partitionGuid, blueprintPrimaryInstanceGuid)

	if blueprint == nil then
		error('BlueprintManagerClient:SpawnObjectBlueprint() couldnt find the specified instance')
		return
	end


	local objectBlueprint = _G[blueprint.typeInfo.name](blueprint)

	-- print('BlueprintManagerClient:SpawnObjectBlueprint() blueprint type: ' .. blueprint.typeInfo.name .. " | ID: " .. uniqueString .. " | Instance: " .. tostring(blueprintPrimaryInstanceGuid))

	local params = EntityCreationParams()
	params.transform = linearTransform
	params.variationNameHash = variationNameHash

	g_InitAll = true
	g_CurrentlySpawningBlueprint = uniqueString

	spawnedObjectEntities[uniqueString] = {}

	local entityBus = EntityManager:CreateEntitiesFromBlueprint(objectBlueprint, params)

	if entityBus == nil then
		--error('entityBus was nil')
		g_InitAll = false
		return
	end

	local objectEntities = entityBus.entities

	for _, entity in pairs(objectEntities) do
		entity:Init(Realm.Realm_Client, true)
		entity:FireEvent("Start")

		local length = #spawnedObjectEntities[uniqueString]
		spawnedObjectEntities[uniqueString][length + 1] = entity
	end
	g_CurrentlySpawningBlueprint = ""
	g_InitAll = false
end

function BlueprintManagerClient:OnDeleteBlueprint(uniqueString)
    
	m_Logger:Write("Client received request to delete blueprint with uniqueString: " .. uniqueString)
	
	if spawnedObjectEntities[uniqueString] ~= nil then
        for i, entity in pairs(spawnedObjectEntities[uniqueString]) do
            if entity ~= nil then
                entity:Destroy()
            end
        end

        spawnedObjectEntities[uniqueString] = nil
    else
        error('BlueprintManagerClient:OnDeleteBlueprint(uniqueString): Could not find a blueprint with the ID: ' .. uniqueString .. '. The objects was successfully deleted on the server however. How could this happen?')
        return
    end
end

function BlueprintManagerClient:OnMoveBlueprint(uniqueString, newLinearTransform)
	
	m_Logger:Write("Client received request to move blueprint with uniqueString: " .. uniqueString)
	
	if spawnedObjectEntities[uniqueString] == nil then
        error('BlueprintManagerClient:OnMoveBlueprint(uniqueString, newLinearTransform): Could not find a blueprint with the ID: ' .. uniqueString)
        return
	end
	
	for i, l_Entity in pairs(spawnedObjectEntities[uniqueString]) do


		local s_Entity = SpatialEntity(l_Entity)
		
		if s_Entity ~= nil then
			s_Entity.transform = newLinearTransform
			s_Entity:FireEvent("Disable")
			s_Entity:FireEvent("Enable")
		end
	end
end

function BlueprintManagerClient:OnLevelLoadingInfo(info)
	if info == 'Sending spawn messages' then
		NetEvents:SendLocal('RequestPostSpawnedObjects')
	end
end

function BlueprintManagerClient:OnSpawnPostSpawnedObject(uniqueString, partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, variationNameHash, enabled)
	if partitionGuid == nil or
       blueprintPrimaryInstanceGuid == nil or
       linearTransform == nil or 
       uniqueString == nil or
       enabled == nil then
	   error('BlueprintManagerClient: SpawnObjectBlueprint(partitionGuid, blueprintPrimaryInstanceGuid, linearTransform) - One or more parameters are nil')
	end

	BlueprintManagerClient:OnSpawnBlueprint(uniqueString, partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, variationNameHash)

	-- print("OnSpawnPostSpawnedObject")
	-- print(enabled)
	if not enabled then
		self:OnEnableEntity(uniqueString, enable)
	end
end


g_BlueprintManagerClient = BlueprintManagerClient()

