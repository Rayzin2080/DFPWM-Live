local version="19ed699ba3fb004960f812d38533e9b309f38131"
local wsurl = "ws://my.tld:1234"
local rawtape = peripheral.find("tape_drive")
local peripheralCalls = 0

local tape = setmetatable({}, {
    __index = function(_, i)
        if rawtape[i] then
            return function(...)
                peripheralCalls = peripheralCalls + 1
                return rawtape[i](...)
            end
        end
    end
})

local running = true
local wss
local total = 0
local startTimer
local repeatingTimer
local size = tape.getSize()

local cData = "" -- cummulative Data

tape.seek(-math.huge)
tape.setSpeed(2)

local curWrite = tape.getPosition()

local buffer = 5 * 9000 -- 5 seconds buffer at the end

local function wipeTape()
    tape.stop()
    tape.seek(-math.huge)
    tape.write(("\000"):rep(size))
    tape.seek(-math.huge)
end

local handler = {
    ["websocket_success"] = function(url, ws)
        if url == wsurl then
            print("Connected!")
            wss = ws
        end
    end,
    ["websocket_failure"] = function(url, why)
        if url == wsurl then
            print("Failed to connect: "..why)
        end
    end,
    ["websocket_closed"] = function(url)
        if url == wsurl then
            running = false
        end
    end,
    ["websocket_message"] = function(url, data)
        if url == wsurl then
            cData = cData .. data
            total = total + #data
        end
    end,
    ["char"] = function(c)
        if c:lower() == "q" then
            running = false
        end
    end,
    ["timer"] = function(t)
        if t == startTimer then
            tape.play()
        elseif t == repeatingTimer then
            local curRead = tape.getPosition()

            if curRead > size - buffer then
                tape.seek((buffer - (size - curRead)) - curRead)
            end

            local bufferHealth = curWrite%(size-buffer) - curRead%(size-buffer)
            if bufferHealth < 2 * 9000 then -- Less than 2 seconds of buffer remaining
                if curWrite + #cData > size then
                    curWrite = curWrite - (size - buffer)
                end
                local prevWrite = curWrite
                tape.seek(curWrite - tape.getPosition())
                tape.write(cData)
                curWrite = tape.getPosition()
                if curWrite > size - buffer then
                    -- We're at the end and need to mirror to the beginning
                    local offsetInBuffer = prevWrite - (size-buffer)
                    local toWrite = cData
                    if offsetInBuffer < 0 then
                        toWrite = cData:sub(-offsetInBuffer)
                    end
                    tape.seek(offsetInBuffer - curWrite)
                    tape.write(toWrite)
                elseif prevWrite < buffer then
                    -- We're at the beginning and need to mirror to the end
                    local offsetInBuffer = prevWrite
                    local nPos = (size - buffer) + offsetInBuffer
                    tape.seek(nPos - curWrite)
                    tape.write(cData)
                end
                tape.seek(curRead - tape.getPosition())
                print(curRead .. "/" .. curWrite)

                cData = ""
            end

            repeatingTimer = os.startTimer(1)
        end
    end,
    ["terminate"] = function()
        running = false
    end
}

http.websocketAsync(wsurl)
startTimer = os.startTimer(5)
repeatingTimer = os.startTimer(1)

while running do
    local e = {os.pullEventRaw()}
    if handler[e[1]] then
        handler[e[1]](unpack(e, 2))
    end
end

-- Unfortunately because we have no way of checking wether a websocket is open this is the best we can do
pcall(function() wss.close() end)
print("Connection closed")
print("Data received:",total)
wipeTape()
