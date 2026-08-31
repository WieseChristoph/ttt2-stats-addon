return function(API, Json, normalizeLogLevel, logLevelOrder)
    local configPath = "ttt2_stats/config.json"

    local function getWebsiteHost(website)
        local host = tostring(website or ""):match("^[%w+.-]+://([^/%?#]+)")
        if not host then return "" end

        return host:gsub("^.-@", ""):gsub(":%d+$", "")
    end

    local function ensureDataDirectory()
        if not file.IsDir("ttt2_stats", "DATA") then file.CreateDir("ttt2_stats") end
    end

    local function cleanWebsite(website)
        if type(website) ~= "string" then return "" end
        return string.Trim(website):gsub("/+$", "")
    end

    local function writeConfig(api, config)
        local encoded = api:encodeJson(config, "write configuration")
        if not encoded then return false end

        file.Write(configPath, encoded)
        return true
    end

    function API:loadConfig()
        ensureDataDirectory()
        local defaults = { website = "", token = "", logLevel = "INFO" }
        if not file.Exists(configPath, "DATA") then
            writeConfig(self, defaults)
            self.config = defaults
            self.logLevel = defaults.logLevel
            self:log("INFO", "Configuration file created", { path = configPath })
            self:log("INFO", "Configuration loaded", {
                logLevel = self.logLevel,
                tokenConfigured = false,
                website = "",
            })
            return
        end

        local contents = file.Read(configPath, "DATA") or ""
        local ok, decodedOrError = pcall(Json.decode, contents)
        local configError = not ok and decodedOrError or nil
        local configInvalid = not ok or type(decodedOrError) ~= "table"
        if configInvalid then decodedOrError = {} end

        local decoded = decodedOrError
        local configuredLogLevel = string.upper(tostring(decoded.logLevel or "INFO"))
        local invalidLogLevel = not logLevelOrder[configuredLogLevel]
        self.logLevel = normalizeLogLevel(configuredLogLevel)
        self.config = {
            website = cleanWebsite(decoded.website),
            token = tostring(decoded.token or ""),
            logLevel = self.logLevel,
        }
        writeConfig(self, self.config)

        if configInvalid then
            self:log("WARN", "Configuration file invalid; defaults applied", {
                path = configPath,
                reason = configError or "expected JSON object",
            })
        elseif invalidLogLevel then
            self:log("WARN", "Invalid log level; INFO applied", {
                configured = configuredLogLevel,
                path = configPath,
            })
        end

        self:log("INFO", "Configuration loaded", {
            logLevel = self.logLevel,
            tokenConfigured = self.config.token ~= "",
            website = getWebsiteHost(self.config.website),
        })
    end

    function API:isConfigured()
        if self.config.website == "" then
            if self.lastConfigurationIssue ~= "website" then
                self:log("WARN", "No website configured")
                self.lastConfigurationIssue = "website"
            end

            return false
        end

        if self.config.token == "" then
            if self.lastConfigurationIssue ~= "token" then
                self:log("WARN", "No token configured")
                self.lastConfigurationIssue = "token"
            end

            return false
        end

        self.lastConfigurationIssue = nil
        return true
    end
end
