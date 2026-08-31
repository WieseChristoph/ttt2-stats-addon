return function(API, Utils, Json)
    API.sessionKey = nil
    API.sessionAttempt = 0
    API.sessionReady = false
    API.roundDeliveries = {}

    local queuePath = "ttt2_stats/queue"

    local function ensureQueue()
        if not file.IsDir("ttt2_stats", "DATA") then file.CreateDir("ttt2_stats") end
        if not file.IsDir(queuePath, "DATA") then file.CreateDir(queuePath) end
    end

    function API:request(path, body, onSuccess, onFailure)
        if not self:isConfigured() then return false end

        local encodedBody = self:encodeJson(body, "request body", { endpoint = path })
        if not encodedBody then
            if onFailure then onFailure("JSON encoding failed") end
            return false
        end

        local requestStarted = SysTime()
        self:log("DEBUG", "API request started", { endpoint = path, method = "PUT" })

        HTTP({
            url = self.config.website .. path,
            method = "PUT",
            headers = {
                ["Authorization"] = "Bearer " .. self.config.token,
                ["Content-Type"] = "application/json",
            },
            body = encodedBody,
            success = function(code)
                local durationMs = math.floor((SysTime() - requestStarted) * 1000 + 0.5)
                if code >= 200 and code < 300 then
                    self:log("DEBUG", "API request succeeded", {
                        endpoint = path,
                        durationMs = durationMs,
                        status = code,
                    })
                    if onSuccess then onSuccess() end
                else
                    self:log("ERROR", "API request failed", {
                        endpoint = path,
                        durationMs = durationMs,
                        status = code,
                    })
                    if onFailure then onFailure("API returned HTTP " .. tostring(code)) end
                end
            end,
            failed = function(reason)
                local durationMs = math.floor((SysTime() - requestStarted) * 1000 + 0.5)
                self:log("ERROR", "API request failed", {
                    endpoint = path,
                    durationMs = durationMs,
                    reason = reason,
                })
                if onFailure then onFailure(tostring(reason)) end
            end,
        })

        return true
    end

    function API:saveQueuedRound(payload)
        ensureQueue()
        local key = string.gsub(payload.roundKey, "[^%w%-]", "_")
        local path = queuePath .. "/" .. key .. ".json"
        local encodedPayload = self:encodeJson(payload, "queued round", { roundKey = payload.roundKey })
        if not encodedPayload then return nil end

        local alreadyQueued = file.Exists(path, "DATA")
        file.Write(path, encodedPayload)

        if not alreadyQueued then
            local files = file.Find(queuePath .. "/*.json", "DATA")
            self:log("INFO", "Round queued", {
                file = path,
                pending = #files,
                roundKey = payload.roundKey,
            })
        end

        return path
    end

    function API:sendSession()
        if not self.sessionKey then return end

        self.sessionAttempt = self.sessionAttempt + 1
        self:log(self.sessionAttempt == 1 and "INFO" or "DEBUG",
            self.sessionAttempt == 1 and "Session registration started" or "Session registration retry", {
                attempt = self.sessionAttempt,
                map = game.GetMap(),
                sessionKey = self.sessionKey,
            })

        self:request("/api/ingest/v1/sessions", {
            protocolVersion = 1,
            sessionKey = self.sessionKey,
            mapName = game.GetMap(),
            startedAt = self.sessionStartedAt,
        }, function()
            self.sessionReady = true
            self:log("INFO", "Session registered", {
                attempt = self.sessionAttempt,
                map = game.GetMap(),
                sessionKey = self.sessionKey,
            })
            self:flushQueue()
        end, function(reason)
            self.sessionReady = false
            self:log("WARN", "Session registration failed", {
                attempt = self.sessionAttempt,
                map = game.GetMap(),
                reason = reason,
                sessionKey = self.sessionKey,
            })
        end)
    end

    function API:startSession()
        self.sessionStartedAt = Utils.getIsoDate()
        self.sessionKey = game.GetMap() .. "-" .. tostring(os.time())
        self.sessionAttempt = 0
        self.sessionReady = false
        self:sendSession()
    end

    function API:sendRound(payload)
        local queuedFile = self:saveQueuedRound(payload)
        if not queuedFile then return false end

        if not self.sessionReady then
            self:log("INFO", "Round waiting for session registration", {
                roundKey = payload.roundKey,
            })
            return false
        end

        if self.roundDeliveries[queuedFile] then return false end

        self.roundDeliveries[queuedFile] = true
        local requestStarted = self:request("/api/ingest/v1/rounds", payload, function()
            self.roundDeliveries[queuedFile] = nil
            if file.Exists(queuedFile, "DATA") then file.Delete(queuedFile) end
            self:log("INFO", "Round recorded", {
                roundKey = payload.roundKey,
            })
        end, function(reason)
            self.roundDeliveries[queuedFile] = nil
            self:log("WARN", "Round delivery failed", {
                reason = reason,
                roundKey = payload.roundKey,
            })
        end)
        if not requestStarted then
            self.roundDeliveries[queuedFile] = nil
            return false
        end

        return true
    end

    function API:flushQueue()
        if not self.sessionReady then return end

        ensureQueue()

        local files = file.Find(queuePath .. "/*.json", "DATA")
        local valid = 0
        local scheduled = 0
        local discarded = 0
        for _, filename in ipairs(files) do
            local path = queuePath .. "/" .. filename
            local ok, payload = pcall(Json.decode, file.Read(path, "DATA") or "")
            if ok and type(payload) == "table" then
                valid = valid + 1
                if self:sendRound(payload) then scheduled = scheduled + 1 end
            else
                discarded = discarded + 1
                file.Delete(path)
                self:log("WARN", "Discarded invalid queue file", {
                    file = path,
                    reason = payload or "invalid JSON payload",
                })
            end
        end

        if #files > 0 then
            self:log("DEBUG", "Queue flush completed", {
                discarded = discarded,
                found = #files,
                scheduled = scheduled,
                valid = valid,
            })
        end
    end

    function API:queueRetry()
        timer.Create("TTT2Stats.Retry", 30, 0, function()
            if not self.sessionReady then self:sendSession() end
            self:flushQueue()
        end)
        self:log("INFO", "Retry timer started", { intervalSeconds = 30 })
    end
end
