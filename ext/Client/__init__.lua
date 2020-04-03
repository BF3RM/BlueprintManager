class 'BlueprintManagerClient'

function BlueprintManagerClient:__init()
	print("Initializing BlueprintManagerClient")
	self:RegisterVars()
	self:RegisterEvents()
end

function BlueprintManagerClient:RegisterVars()
end

local spawnedObjectEntities = { }

function BlueprintManagerClient:RegisterEvents()
    Events:Subscribe('Player:Connected', self, self.PlayerConnected)

    Events:Subscribe('BlueprintManager:SpawnBlueprintFromClient', self, self.OnSpawnBlueprintFromClient)
    Events:Subscribe('BlueprintManager:DeleteBlueprintFromClient', self, self.OnDeleteBlueprintFromClient)
    Events:Subscribe('BlueprintManager:MoveBlueprintFromClient', self, self.OnMoveBlueprintFromClient)

    NetEvents:Subscribe('SpawnBlueprint', self, self.OnSpawnBlueprint)
    NetEvents:Subscribe('DeleteBlueprint', self, self.OnDeleteBlueprint)
    NetEvents:Subscribe('MoveBlueprint', self, self.OnMoveBlueprint)
    NetEvents:Subscribe('SpawnPostSpawnedObjects', self, self.OnSpawnPostSpawnedObject)
    NetEvents:Subscribe('EnableEntity', self, self.OnEnableEntity)
end

function BlueprintManagerClient:OnEnableEntity(uniqueString, enable)
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

    local blueprint = ResourceManager:FindInstanceByGUID(partitionGuid, blueprintPrimaryInstanceGuid)

	if blueprint == nil then
		error('BlueprintManagerClient:SpawnObjectBlueprint() couldnt find the specified instance')
		return
	end


	local objectBlueprint = _G[blueprint.typeInfo.name](blueprint)

	-- print('BlueprintManagerClient:SpawnObjectBlueprint() blueprint type: ' .. blueprint.typeInfo.name .. " | ID: " .. uniqueString .. " | Instance: " .. tostring(blueprintPrimaryInstanceGuid))

	local params = EntityCreationParams()
	params.transform = linearTransform
	params.variationNameHash = variationNameHash
	
    local objectEntities = EntityManager:CreateEntitiesFromBlueprint(objectBlueprint, params)
    
	for i, entity in pairs(objectEntities) do
		entity:Init(Realm.Realm_Client, true)
		entity:FireEvent("Start")
	end
	
	spawnedObjectEntities[uniqueString] = objectEntities
end

function BlueprintManagerClient:OnDeleteBlueprint(uniqueString)
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

function BlueprintManagerClient:PlayerConnected(player)
	NetEvents:SendLocal('RequestPostSpawnedObjects')
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

