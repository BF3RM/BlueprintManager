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
	    print('BlueprintManagerClient: SpawnObjectBlueprint(partitionGuid, blueprintPrimaryInstanceGuid, linearTransform) - One or more parameters are nil')
	end

	if spawnedObjectEntities[uniqueString] ~= nil then
		print('Object with id ' .. uniqueString .. ' already existed as a spawned entity!')
		return
	end

	variationNameHash = variationNameHash or 0

    local blueprint = ResourceManager:FindInstanceByGUID(partitionGuid, blueprintPrimaryInstanceGuid)

	if blueprint == nil then
		error('BlueprintManagerClient:SpawnObjectBlueprint() couldnt find the specified instance')
		return
	end
--[[
	local objectBlueprint = nil

	if blueprint.typeInfo.name == 'VehicleBlueprint' then
		objectBlueprint = VehicleBlueprint(blueprint)
	elseif blueprint.typeInfo.name == 'ObjectBlueprint' then
		objectBlueprint = ObjectBlueprint(blueprint)
	--elseif blueprint.typeInfo.name == 'PrefabBlueprint' then
	--	objectBlueprint = PrefabBlueprint(blueprint)
	--elseif blueprint.typeInfo.name == 'SpatialPrefabBlueprint' then
	--	objectBlueprint = SpatialPrefabBlueprint(blueprint)
	elseif blueprint.typeInfo.name == 'EffectBlueprint' then
		objectBlueprint = EffectBlueprint(blueprint)
	else
		error('BlueprintManagerClient:SpawnObjectBlueprint() blueprint is not of any type that is supported')
		print('Actual type: ' .. blueprint.typeInfo.name)
		return
	end]]

	

	local objectBlueprint = blueprint

	print('BlueprintManagerClient:SpawnObjectBlueprint() blueprint type: ' .. blueprint.typeInfo.name)



	local params = EntityCreationParams()
	params.transform = linearTransform
	params.variationNameHash = variationNameHash
	
    local objectEntities = EntityManager:CreateClientEntitiesFromBlueprint(objectBlueprint, params)
    
	for i, entity in pairs(objectEntities) do
		entity:Init(Realm.Realm_Client, true)
<<<<<<< HEAD

		s_Entity:FireEvent("Disable")
		s_Entity:FireEvent("Enable")

		entity:FireEvent("Start")

		VisualEnvironmentManager.dirty = true
=======
		entity:FireEvent("Start")
>>>>>>> a8fe6020a9b13118c65fbe07c069c71332c36553
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
<<<<<<< HEAD

			--s_Entity:FireEvent("Reset")

			s_Entity:FireEvent("Disable")
			s_Entity:FireEvent("Enable")
=======
			s_Entity:FireEvent("Reset")
>>>>>>> a8fe6020a9b13118c65fbe07c069c71332c36553
		end
	end
end

function BlueprintManagerClient:PlayerConnected(player)
	NetEvents:SendLocal('RequestPostSpawnedObjects')
end

function BlueprintManagerClient:OnSpawnPostSpawnedObject(uniqueString, partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, variationNameHash)
	if partitionGuid == nil or
       blueprintPrimaryInstanceGuid == nil or
       linearTransform == nil or 
       uniqueString == nil then
	   error('BlueprintManagerClient: SpawnObjectBlueprint(partitionGuid, blueprintPrimaryInstanceGuid, linearTransform) - One or more parameters are nil')
	end

	BlueprintManagerClient:OnSpawnBlueprint(uniqueString, partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, variationNameHash)
end


g_BlueprintManagerClient = BlueprintManagerClient()

