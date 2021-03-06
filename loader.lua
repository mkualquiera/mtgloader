DEFAULTBACK = "http://cloud-3.steamusercontent.com/ugc/1662355594061186486/19DA641099199091F9AFF7103EBE7D07943D7B47/"

-- Scryfall API module
Scryfall = {}

Scryfall.getCardDataBySomething = function(text, callback)
    local id = string.match(text, "([0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+)")
    if id then
        Scryfall.getCardDataById(id, callback)
    else
        Scryfall.getCardDataByName(text, callback)
    end
end

Scryfall.getCardDataById = function(id, callback)
    Scryfall.getCardDataByURI("https://api.scryfall.com/cards/" .. id, callback)
end

Scryfall.getCardDataByURI = function(uri, callback)
    WebRequest.get(uri, function(req)
        local cardData = JSON.decode(req.text)
        return callback(cardData)
    end)
end

Scryfall.getCardDataByName = function(cardName, callback)
    WebRequest.get("https://api.scryfall.com/cards/search?q=" .. cardName .. "&unique=cards", function(req)
        local response = JSON.decode(req.text)
        if #response.data > 1 then
            -- Search for the correct card, since we may get multiple results.
            for i, cardData in ipairs(response.data) do
                if cardData.name == cardName then
                    return callback(cardData)
                end
            end
        else
            return callback(response.data[1])
        end
        printToAll(cardName .. " not found!")
        return
    end)
end

-- MTGLoader module.
MTGLoader = {}
MTGLoader.spawnDeckObject = function(deckDescriptor, position)
    if #(deckDescriptor.cards) == 0 then
        printToAll("Attempted to build empty deck")
        return
    end
    -- When we only have a single card, we just spawn it as a Card object.
    if #(deckDescriptor.cards) == 1 then
        if ((deckDescriptor.cards[1].count + 1) - 1) == 1 then
            local card = spawnObject({
                type = "Card",
                position = position,
                rotation = {
                    x = 0,
                    y = 180,
                    z = 180
                }
            })
            card.setCustomObject({
                face = deckDescriptor.cards[1].face,
                back = deckDescriptor.cards[1].back,
                width = 1,
                height = 1
            })
            card.setName(deckDescriptor.cards[1].name)
            card.setDescription(deckDescriptor.cards[1].description)
            return
        end
    end

    -- If we do have more than one, then we must build the JSON object.
    local deck = {}
    deck["Name"] = "DeckCustom"
    deck["DeckIDs"] = {}
    deck["CustomDeck"] = {}
    deck["ContainedObjects"] = {}
    deck["Transform"] = {
        posX = position.x,
        posY = position.y,
        posZ = position.z,
        rotX = 0,
        rotY = 180,
        rotZ = 180,
        scaleX = 1,
        scaleY = 1,
        scaleZ = 1
    }
    for i, cardDescriptor in ipairs(deckDescriptor.cards) do
        -- Insert the images into the CustomDeck

        -- Encode the key with a random string because otherwise this will
        -- be treated as a list, but we need it to be a dictionary.
        deck["CustomDeck"]["KADFSJIIUREJWEFMCZXNBFDWHTI" .. i] = {
            FaceURL = cardDescriptor.face,
            BackURL = cardDescriptor.back,
            NumHeight = 1,
            NumWidth = 1,
            BackIsHidden = true
        }

        for j = 1, cardDescriptor.count, 1 do
            -- Insert into DeckIDs
            table.insert(deck["DeckIDs"], i * 100)

            -- Insert into ContainedObjects
            table.insert(deck["ContainedObjects"], {
                CardId = i * 100,
                Name = "Card",
                Nickname = cardDescriptor.name,
                Description = cardDescriptor.description,
                Transform = {
                    posX = 0,
                    posY = 0,
                    posZ = 0,
                    rotX = 0,
                    rotY = 180,
                    rotZ = 180,
                    scaleX = 1,
                    scaleY = 1,
                    scaleZ = 1
                }
            })
        end
    end
    deckJSON = JSON.encode(deck)
    -- Remove the random string from the text JSON.
    deckJSON = deckJSON:gsub("KADFSJIIUREJWEFMCZXNBFDWHTI", "")
    -- log(deckJSON)

    -- Spawn the JSON deck itself.
    spawnObjectJSON({
        json = deckJSON
    })
end

function binomial(p, n)
    local sucesses = 0
    for i = 1, n, 1 do
        if math.random() <= p then
            sucesses = sucesses + 1
        end
    end
    return sucesses
end

MTGLoader.createDeckDescriptor = function(namesAndCounts, genSideboard, callback)
    MTGLoader.createDeckDescriptorInternal({
        deck = {
            cards = {}
        },
        sideboard = {}
    }, namesAndCounts, genSideboard, callback)
end

USEFOIL = false

FOILPROBABILITIES = {
    common = 1 / 50,
    uncommon = 1 / 25,
    rare = 1 / 10,
    mythic = 1 / 1
}

function deepCopy(obj, seen)
    -- Handle non-tables and previously-seen tables.
    if type(obj) ~= 'table' then
        return obj
    end
    if seen and seen[obj] then
        return seen[obj]
    end

    -- New table; mark it as seen and copy recursively.
    local s = seen or {}
    local res = {}
    s[obj] = res
    for k, v in pairs(obj) do
        res[deepCopy(k, s)] = deepCopy(v, s)
    end
    return setmetatable(res, getmetatable(obj))
end

function getFoil(url)
    local lastpart, crap = string.match(url, "https://c1.scryfall.com/file/(.+)?(.+)")
    local formated = lastpart:gsub("/", "PATHSEPARATOR") .. ".unity3d"
    local fullurl = "huestudios.mooo.com:81/files/" .. formated
    return fullurl
end

MTGLoader.createDeckDescriptorInternal = function(progress, namesAndCounts, genSideboard, callback)
    if #namesAndCounts == 0 then
        callback(progress)
        return
    end
    local nameAndCount = table.remove(namesAndCounts)
    print("Loading >" .. nameAndCount.name .. "<...")
    Scryfall.getCardDataBySomething(nameAndCount.name, function(cardData)

        local foilProbability = FOILPROBABILITIES[cardData.rarity]
        if not USEFOIL then
            foilProbability = 0
        end
        local foilCount = binomial(foilProbability, nameAndCount.count)
        local normalCount = nameAndCount.count - foilCount

        local newCard = {
            name = cardData.name .. " [" .. cardData.type_line:gsub("???", "-") .. "]",
            count = normalCount,
            back = DEFAULTBACK
        }
        if cardData.image_uris == nil then
            newCard.face = cardData.card_faces[1].image_uris.normal
            newCard.back = cardData.card_faces[2].image_uris.normal
            newCard.description = cardData.card_faces[1].oracle_text .. " // " .. cardData.card_faces[2].oracle_text
        else
            newCard.face = cardData.image_uris.normal
            newCard.description = cardData.oracle_text
        end
        if foilCount > 0 then
            local foiledCard = deepCopy(newCard)
            foiledCard.count = foilCount
            if cardData.image_uris == nil then
                foiledCard.face = getFoil(newCard.face)
                foiledCard.back = getFoil(newCard.back)
            else
                foiledCard.face = getFoil(newCard.face)
            end
            table.insert(progress.deck.cards, foiledCard)
        end
        if normalCount > 0 then
            table.insert(progress.deck.cards, newCard)
        end

        if genSideboard then
            if cardData.all_parts ~= nil then
                for i, part in ipairs(cardData.all_parts) do
                    if (part.component == "token" or string.match(part.type_line, "Emblem")) and part.id ~= newCard.id then
                        local contained = false
                        for i, sideboardCard in ipairs(progress.sideboard) do
                            if sideboardCard.id == part.id then
                                contained = true
                                break
                            end
                        end
                        if not contained then
                            table.insert(progress.sideboard, {
                                name = part.id,
                                id = part.id,
                                count = 1
                            })
                        end
                    end
                end
            end
        end

        MTGLoader.createDeckDescriptorInternal(progress, namesAndCounts, genSideboard, callback)
    end)
end

function mysplit(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

function getNotebookText()
    notebooks = Notes.getNotebookTabs()
    return mysplit(notebooks[#notebooks].body, "\n")
end

function loadFromLines(lines,loadPos)
    local namesAndCounts = {}
    for i, line in ipairs(lines) do
        local count, cardName = string.match(line, "(%d+) (.+)")
        if count and cardName then
            cardName = string.gsub(cardName, '[ \t]+%f[\r\n%z]', '')
            local nameAndCount = {
                name = cardName,
                count = count
            }
            table.insert(namesAndCounts, nameAndCount)
        end
    end
    MTGLoader.createDeckDescriptor(namesAndCounts, true, function(descriptors)
        local deck = descriptors.deck
        MTGLoader.spawnDeckObject(deck, loadPos)
        local sideboard = descriptors.sideboard
        MTGLoader.createDeckDescriptor(sideboard, false, function(descriptors)
            local deck = descriptors.deck
            MTGLoader.spawnDeckObject(deck, {
                x = loadPos.x + 5,
                y = loadPos.y,
                z = loadPos.z
            })
        end)
    end)
end

function onChat(message, player)
    if message == "!deck" then
        printToAll("Loading deck...")

        local loadPos = player.getPointerPosition()
        loadPos.y = 5
        local lines = getNotebookText()
        loadFromLines(lines,loadPos)
        return
    end
    if message == "!foil" then
        USEFOIL = not USEFOIL
        printToAll("USEFOIL is now "..tostring(USEFOIL))
    end
end