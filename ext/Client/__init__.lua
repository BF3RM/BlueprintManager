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

    NetEvents:Subscribe('SpawnObject', self, self.OnSpawnBlueprint)
    NetEvents:Subscribe('SpawnPostSpawnedObjects', self, self.OnSpawnPostSpawnedObject)
    NetEvents:Subscribe('DeleteBlueprint', self, self.OnDeleteBlueprint)
end

function BlueprintManagerClient:OnSpawnBlueprintFromClient(partitionGuid, blueprintPrimaryInstance, linearTransform, uniqueString)
    NetEvents:SendLocal('SpawnBlueprintFromClient', partitionGuid, blueprintPrimaryInstance, linearTransform, uniqueString)
end

function BlueprintManagerClient:OnDeleteBlueprintFromClient(uniqueString)
    NetEvents:SendLocal('DeleteBlueprintFromClient', uniqueString)
end

function BlueprintManagerClient:OnSpawnBlueprint(partitionGuid, blueprintPrimaryInstance, linearTransform, uniqueString) -- this should only be called via NetEvents
	if partitionGuid == nil or
       blueprintPrimaryInstance == nil or
	   linearTransform == nil then
	    print('BlueprintManagerClient: SpawnObjectBlueprint(partitionGuid, blueprintPrimaryInstance, linearTransform) - One or more parameters are nil')
	end

	print("BlueprintManagerClient: partitionGuid: " .. partitionGuid:ToString("D") .. " - blueprintPrimaryInstanceGuid: " .. blueprintPrimaryInstance:ToString("D") .. " linearTransform: " .. tostring(linearTransform))

    local blueprint = ResourceManager:FindInstanceByGUID(partitionGuid, blueprintPrimaryInstanceGuid)

	if blueprint == nil then
		print('BlueprintManagerClient:SpawnObjectBlueprint() couldnt find the specified instance')
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
		print('BlueprintManagerClient:SpawnObjectBlueprint() blueprint is not of any type that is supported')
		print('Actual type: ' .. blueprint.typeName)
		return
	end

	print('BlueprintManagerClient: Blueprint TypeName: ' .. objectBlueprint.typeName)
	print('BlueprintManagerClient: Got spawn object event for '.. objectBlueprint.name)
	
	
    local objectEntities = EntityManager:CreateClientEntitiesFromBlueprint(objectBlueprint, linearTransform)
    
	for i, entity in pairs(objectEntities) do
		entity:Init(Realm.Realm_Client, true)
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

function BlueprintManagerClient:PlayerConnected(player)
	print("ClientObjectsManager:OnLoaded(): sending requestPostSpawnedObjects client -> server")
	NetEvents:SendLocal('RequestPostSpawnedObjects')
end

function BlueprintManagerClient:OnSpawnPostSpawnedObject(partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, uniqueString)
	if partitionGuid == nil or
       blueprintPrimaryInstanceGuid == nil or
       linearTransform == nil or 
       uniqueString == nil then
	   print('BlueprintManagerClient: SpawnObjectBlueprint(partitionGuid, blueprintPrimaryInstanceGuid, linearTransform) - One or more parameters are nil')
	end

	print('BlueprintManagerClient:OnSpawnPostSpawnedObjects() : Spawning postSpawnedObject. PartitionGuid: ' .. partitionGuid:ToString("D") .. ' - PrimaryInstanceGuid: ' .. blueprintPrimaryInstanceGuid)
	print('BlueprintManagerClient:OnSpawnPostSpawnedObjects() : lineartransform of postSpawnedObject:' .. tostring(linearTransform))

	BlueprintManagerClient:OnSpawnBlueprint(partitionGuid, blueprintPrimaryInstanceGuid, linearTransform, uniqueString)
end


g_BlueprintManagerClient = BlueprintManagerClient()

