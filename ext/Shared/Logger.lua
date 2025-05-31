---@class Logger
Logger = class "Logger"

---@param p_ClassName string
---@param p_ActivateLogging boolean
---@param p_Category LoggerCategory[]|LoggerCategory|string|nil
function Logger:__init(p_ClassName, p_ActivateLogging, p_Category)
	if type(p_ClassName) ~= "string" then
		-- error("Logger: Wrong arguments creating object, className is not a string. ClassName: " .. tostring(p_ClassName))
		return
	elseif type(p_ActivateLogging) ~= "boolean" then
		-- error("Logger: Wrong arguments creating object, ActivateLogging is not a boolean. ActivateLogging: " .. tostring(p_ActivateLogging))
		return
	end

	-- print("Creating object with: "..p_ClassName..", "..tostring(p_ActivateLogging))
	self.m_Debug = p_ActivateLogging
	self.m_ClassName = p_ClassName
	self.m_Category = p_Category
end

---@param p_Message boolean|integer|number|string|table
---@param p_Category LoggerCategory|string|nil
function Logger:Write(p_Message, p_Category)
	if self.m_ClassName == nil then
		return
	end

	--category of this print is enabled
	if p_Category ~= nil then
		goto continue
	end

	--logger not in debug, print all also disabled
	if not self.m_Debug then
		-- logger has no category
		if self.m_Category == nil then
			return
		end

		--logger category can be a string or a string[]
		if type(self.m_Category) == "string" then
			-- make sure the category is enabled and matches the category of this print if there is one
			if p_Category == nil or p_Category == self.m_Category then
				goto continue
			end
		elseif type(self.m_Category) == "table" then
			for _, l_Category in pairs(self.m_Category) do
				if p_Category == nil or p_Category == l_Category then
					goto continue
				end
			end
		end

		return
	end

	::continue::
	if type(p_Message) == "table" then
		-- print("[" .. self.m_ClassName .. "] Table:")
		-- print(p_Message)
	else
		-- print("[" .. self.m_ClassName .. "] " .. tostring(p_Message))
	end
end

---@param p_Message boolean|integer|number|string
function Logger:Warning(p_Message)
	if self.m_ClassName == nil then
		return
	end

	-- print("[" .. self.m_ClassName .. "] WARNING: " .. tostring(p_Message))
end

---@param p_Message boolean|integer|number|string
function Logger:Error(p_Message)
	if self.m_ClassName == nil then
		return
	end

	-- error("[" .. self.m_ClassName .. "] " .. tostring(p_Message) .. " ")
end

return Logger
